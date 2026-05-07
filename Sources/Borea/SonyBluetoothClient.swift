import Foundation
import IOBluetooth

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

final class SonyBluetoothClient: NSObject {
    private static let serviceUUIDBytes: [UInt8] = [
        0x96, 0xcc, 0x20, 0x3e, 0x50, 0x68, 0x46, 0xad,
        0xb3, 0x2d, 0xe3, 0x16, 0xf5, 0xe0, 0x69, 0xba
    ]

    private let queue = DispatchQueue(label: "dev.local.Borea.bluetooth")
    private var channel: IOBluetoothRFCOMMChannel?
    private var connectedDevice: IOBluetoothDevice?
    private var sequence: UInt8 = 0
    private var incomingBuffer = Data()
    private var recentlyHandledFrames: [String: Date] = [:]
    private(set) var lastFrameSummary = "Last headset frame: none"
    private(set) var diagnosticsSummary = "Diagnostics: idle"
    private var pendingMode: SonyMode?
    private var pendingModeExpiresAt: Date?
    private var batteryRefreshTimer: DispatchSourceTimer?

    var onStateChange: ((ConnectionState) -> Void)?
    var onModeChange: ((SonyMode) -> Void)?
    var onBatteryChange: ((BatteryReport?) -> Void)?

    private(set) var connectionState: ConnectionState = .idle {
        didSet { onStateChange?(connectionState) }
    }

    private(set) var batteryReport: BatteryReport? {
        didSet { onBatteryChange?(batteryReport) }
    }

    private(set) var mode: SonyMode? {
        didSet {
            if let mode {
                onModeChange?(mode)
            } else {
                onStateChange?(connectionState)
            }
        }
    }

    var ambientLevel: Int {
        if case let .ambient(level, _) = mode { return level }
        return lastAmbientLevel
    }

    var focusOnVoice: Bool {
        if case let .ambient(_, focusOnVoice) = mode { return focusOnVoice }
        return lastFocusOnVoice
    }

    var statusText: String {
        switch connectionState {
        case .idle:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            if let mode {
                return "Connected - \(mode.title)"
            }
            return "Connected - Mode unknown"
        case let .failed(message):
            return "Error: \(message)"
        }
    }

    var isSwitchingMode: Bool {
        guard let pendingModeExpiresAt else { return false }
        return Date() < pendingModeExpiresAt
    }

    private var lastAmbientLevel = 10
    private var lastFocusOnVoice = false

    func start() {
        Log.info("Starting")
        logPairedDevices()

        if findPairedHeadset() != nil {
            connectionState = .idle
            connect()
        } else {
            connectionState = .failed("Pair WH-1000XM4 in System Settings first")
        }
    }

    func connect() {
        guard connectionState != .connecting else { return }
        Log.info("Connecting to WH-1000XM4")
        connectionState = .connecting

        queue.async { [weak self] in
            self?.prepareConnection()
        }
    }

    func disconnect() {
        Log.info("Disconnecting")
        queue.async { [weak self] in
            guard let self else { return }
            self.channel?.close()
            self.channel = nil
            self.incomingBuffer.removeAll()
            self.recentlyHandledFrames.removeAll()
            self.stopBatteryRefresh()
            let device = self.connectedDevice ?? self.findPairedHeadset()
            let closeStatus = device?.closeConnection()
            Log.debug("closeConnection status=\(closeStatus.map(String.init) ?? "no device")")
            self.connectedDevice = nil
            DispatchQueue.main.async {
                self.pendingMode = nil
                self.pendingModeExpiresAt = nil
                self.batteryReport = nil
                self.connectionState = .idle
            }
        }
    }

    func setMode(_ mode: SonyMode) {
        Log.info("Switching to \(mode.title)")
        switch mode {
        case let .ambient(level, focusOnVoice):
            lastAmbientLevel = level
            lastFocusOnVoice = focusOnVoice
        case .noiseCancelling, .off:
            break
        }

        self.mode = mode
        pendingMode = mode
        pendingModeExpiresAt = Date().addingTimeInterval(0.7)
        send(mode: mode)
    }

    func setAmbientLevel(_ level: Int) {
        let clamped = max(1, min(20, level))
        lastAmbientLevel = clamped
        setMode(.ambient(level: clamped, focusOnVoice: focusOnVoice))
    }

    func setFocusOnVoice(_ enabled: Bool) {
        lastFocusOnVoice = enabled
        setMode(.ambient(level: ambientLevel, focusOnVoice: enabled))
    }

    private func prepareConnection() {
        guard let device = findPairedHeadset() else {
            Log.error("No paired WH-1000XM4 device found")
            DispatchQueue.main.async {
                self.connectionState = .failed("WH-1000XM4 is not paired")
            }
            return
        }

        let deviceName = device.nameOrAddress ?? device.name ?? "<unknown>"
        Log.debug("Selected device: \(deviceName), connected=\(device.isConnected())")

        if !device.isConnected() {
            let status = device.openConnection()
            Log.debug("openConnection status=\(status), connected=\(device.isConnected())")
        }

        let serviceUUID = Self.serviceUUIDBytes.withUnsafeBufferPointer { buffer -> IOBluetoothSDPUUID? in
            IOBluetoothSDPUUID(bytes: buffer.baseAddress, length: buffer.count)
        }

        guard let serviceUUID else {
            DispatchQueue.main.async {
                self.connectionState = .failed("Could not create Sony service UUID")
            }
            return
        }

        let service = findSonyService(on: device, uuid: serviceUUID)
        guard let service else {
            Log.error("Sony control service not found")
            DispatchQueue.main.async {
                self.connectionState = .failed("Sony control service not found")
            }
            return
        }

        var channelID = BluetoothRFCOMMChannelID()
        let channelIDStatus = service.getRFCOMMChannelID(&channelID)
        Log.debug("getRFCOMMChannelID status=\(channelIDStatus), channelID=\(channelID)")
        guard channelIDStatus == kIOReturnSuccess else {
            DispatchQueue.main.async {
                self.connectionState = .failed("RFCOMM channel not found (\(channelIDStatus))")
            }
            return
        }

        DispatchQueue.main.async {
            self.openChannel(device: device, channelID: channelID)
        }
    }

    private func openChannel(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) {
        var openedChannel: IOBluetoothRFCOMMChannel?
        let openStatus = device.openRFCOMMChannelSync(&openedChannel, withChannelID: channelID, delegate: self)
        Log.debug("openRFCOMMChannelSync status=\(openStatus), channelOpen=\(openedChannel?.isOpen() ?? false)")
        guard openStatus == kIOReturnSuccess, let openedChannel else {
            connectionState = .failed("Open RFCOMM failed (\(openStatus))")
            return
        }

        channel = openedChannel
        connectedDevice = device
        diagnosticsSummary = "Diagnostics: RFCOMM channel \(channelID) open"
        connectionState = .connected
        Log.info("Connected")
        refreshBattery()
        startBatteryRefresh()
        queryState()
    }

    private func findPairedHeadset() -> IOBluetoothDevice? {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let candidates = devices.filter { device in
            let name = device.nameOrAddress ?? device.name ?? ""
            return name.localizedCaseInsensitiveContains("WH-1000XM4")
        }

        return candidates.sorted { lhs, rhs in
            let leftName = lhs.nameOrAddress ?? lhs.name ?? ""
            let rightName = rhs.nameOrAddress ?? rhs.name ?? ""

            if lhs.isConnected() != rhs.isConnected() {
                return lhs.isConnected()
            }

            if leftName.hasPrefix("LE_") != rightName.hasPrefix("LE_") {
                return !leftName.hasPrefix("LE_")
            }

            return leftName < rightName
        }.first
    }

    private func findSonyService(on device: IOBluetoothDevice, uuid: IOBluetoothSDPUUID) -> IOBluetoothSDPServiceRecord? {
        if let service = device.getServiceRecord(for: uuid) {
            Log.debug("Sony service found in cached SDP records")
            return service
        }

        Log.debug("Sony service absent from cache; starting SDP query")
        let queryStatus = device.performSDPQuery(nil, uuids: [uuid])
        Log.debug("performSDPQuery status=\(queryStatus)")

        guard queryStatus == kIOReturnSuccess else { return nil }

        for attempt in 1...30 {
            Thread.sleep(forTimeInterval: 0.1)
            if let service = device.getServiceRecord(for: uuid) {
                Log.debug("Sony service found after SDP poll \(attempt)")
                return service
            }
        }

        return nil
    }

    private func logPairedDevices() {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        Log.debug("Paired Bluetooth devices: \(devices.count)")
        for device in devices {
            let name = device.nameOrAddress ?? device.name ?? "<unknown>"
            Log.debug("paired name=\(name), connected=\(device.isConnected()), address=\(device.addressString ?? "<unknown>")")
        }
    }

    private func send(mode: SonyMode) {
        guard connectionState == .connected else {
            Log.debug("Ignoring send while not connected: \(connectionState)")
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            guard let channel = self.channel, channel.isOpen() else {
                Log.debug("Ignoring send because RFCOMM channel is not open")
                return
            }
            let packet = SonyProtocol.command(for: mode, sequence: self.sequence)
            Log.debug("Sending \(mode.title), seq=\(self.sequence), bytes=\(packet.xm4Hex)")
            self.sequence ^= 1

            let status = packet.withUnsafeBytes { rawBuffer -> IOReturn in
                guard let baseAddress = rawBuffer.baseAddress else { return kIOReturnBadArgument }
                return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(packet.count))
            }

            Log.debug("writeSync status=\(status)")
            if status != kIOReturnSuccess {
                DispatchQueue.main.async {
                    self.connectionState = .failed("Write failed (\(status))")
                }
            }
        }
    }

    private func queryState() {
        guard connectionState == .connected else { return }

        queue.async { [weak self] in
            guard let self else { return }
            guard let channel = self.channel, channel.isOpen() else {
                Log.debug("Ignoring state query because RFCOMM channel is not open")
                return
            }

            let packet = SonyProtocol.stateQuery(sequence: self.sequence)
            Log.debug("Sending state query, seq=\(self.sequence), bytes=\(packet.xm4Hex)")
            self.sequence ^= 1

            let status = packet.withUnsafeBytes { rawBuffer -> IOReturn in
                guard let baseAddress = rawBuffer.baseAddress else { return kIOReturnBadArgument }
                return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(packet.count))
            }

            Log.debug("state query writeSync status=\(status)")
        }
    }

    private func startBatteryRefresh() {
        stopBatteryRefresh()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.refreshBattery()
        }
        batteryRefreshTimer = timer
        timer.resume()
    }

    private func stopBatteryRefresh() {
        batteryRefreshTimer?.cancel()
        batteryRefreshTimer = nil
    }

    private func refreshBattery() {
        queue.async { [weak self] in
            let report = BatteryReader.readHeadsetBattery()
            Log.info("Battery: \(report?.title ?? "unavailable")")
            DispatchQueue.main.async {
                self?.batteryReport = report
            }
        }
    }

    private func acknowledge(frame: SonyFrame) {
        guard frame.dataType != 1 else { return }
        guard let channel, channel.isOpen() else { return }

        let packet = SonyProtocol.acknowledgement(for: frame)
        Log.debug("ACK frame seq=\(frame.sequence) as next seq, bytes=\(packet.xm4Hex)")
        let status = packet.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else { return kIOReturnBadArgument }
            return channel.writeSync(UnsafeMutableRawPointer(mutating: baseAddress), length: UInt16(packet.count))
        }
        Log.debug("ACK writeSync status=\(status)")
    }

    private func appendIncomingBytes(_ data: Data) {
        Log.debug("Received raw bytes: \(data.xm4Hex)")
        incomingBuffer.append(data)

        while let startIndex = incomingBuffer.firstIndex(of: 62),
              let endIndex = incomingBuffer[(startIndex + 1)...].firstIndex(of: 60) {
            let frameData = incomingBuffer[startIndex...endIndex]
            incomingBuffer.removeSubrange(...endIndex)

            if let frame = SonyProtocol.parseFrame(Data(frameData)) {
                let payloadHex = frame.payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                let summary = "Last headset frame: type \(frame.dataType), \(frame.payload.count)b \(payloadHex)"
                Log.debug("Parsed Sony frame type=\(frame.dataType), seq=\(frame.sequence), payload=\(payloadHex)")
                acknowledge(frame: frame)
                guard !isRecentlyHandled(frame) else {
                    Log.debug("Ignoring duplicate frame type=\(frame.dataType), seq=\(frame.sequence), payload=\(payloadHex)")
                    continue
                }

                if let mode = SonyProtocol.mode(from: frame) {
                    DispatchQueue.main.async {
                        self.lastFrameSummary = summary
                        self.setObservedMode(mode)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.lastFrameSummary = summary
                        self.onStateChange?(self.connectionState)
                    }
                }
            }
        }

        if incomingBuffer.count > 4096 {
            incomingBuffer.removeAll()
        }
    }

    private func setObservedMode(_ observedMode: SonyMode) {
        if let pendingMode, let pendingModeExpiresAt {
            if Date() < pendingModeExpiresAt, !observedMode.hasSameModeKind(as: pendingMode) {
                Log.debug("Ignoring stale observed mode \(observedMode.title); pending \(pendingMode.title)")
                onStateChange?(connectionState)
                return
            }

            if observedMode.hasSameModeKind(as: pendingMode) || Date() >= pendingModeExpiresAt {
                self.pendingMode = nil
                self.pendingModeExpiresAt = nil
            }
        }

        switch observedMode {
        case let .ambient(level, focusOnVoice):
            lastAmbientLevel = level
            lastFocusOnVoice = focusOnVoice
        case .noiseCancelling, .off:
            break
        }

        if mode != observedMode {
            mode = observedMode
        } else {
            onStateChange?(connectionState)
        }
    }
}

extension SonyBluetoothClient: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        Log.debug("rfcommChannelData length=\(dataLength)")
        let data = Data(bytes: dataPointer, count: dataLength)
        queue.async { [weak self] in
            self?.appendIncomingBytes(data)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Log.info("Disconnected")
        queue.async { [weak self] in
            guard let self else { return }
            self.channel = nil
            self.incomingBuffer.removeAll()
            self.recentlyHandledFrames.removeAll()
            self.stopBatteryRefresh()
            self.connectedDevice = nil
            DispatchQueue.main.async {
                self.pendingMode = nil
                self.pendingModeExpiresAt = nil
                self.batteryReport = nil
                self.connectionState = .idle
            }
        }
    }
}

private extension SonyBluetoothClient {
    func isRecentlyHandled(_ frame: SonyFrame) -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-8)
        recentlyHandledFrames = recentlyHandledFrames.filter { $0.value >= cutoff }

        let signature = "\(frame.dataType):\(frame.sequence):\(frame.payload.xm4Hex)"
        if recentlyHandledFrames[signature] != nil {
            return true
        }

        recentlyHandledFrames[signature] = now
        return false
    }
}

private extension SonyMode {
    func hasSameModeKind(as other: SonyMode) -> Bool {
        switch (self, other) {
        case (.noiseCancelling, .noiseCancelling), (.ambient, .ambient), (.off, .off):
            return true
        default:
            return false
        }
    }
}
