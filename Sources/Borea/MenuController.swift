import AppKit

final class MenuController: NSObject {
    private let client: SonyBluetoothClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let statusHeaderView = StatusHeaderView()
    private let focusOnVoiceItem = NSMenuItem(title: "Focus on Voice", action: #selector(toggleFocusOnVoice), keyEquivalent: "v")

    private let modePickerView = ModePickerView()
    private let ambientTopSeparatorItem = NSMenuItem.separator()
    private let ambientBottomSeparatorItem = NSMenuItem.separator()
    private let volumeSeparatorItem = NSMenuItem.separator()
    private let ambientLevelItem = NSMenuItem()
    private let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: #selector(volumeChanged(_:)))
    private let volumeLabel = NSTextField(labelWithString: "Volume")
    private let volumeValueLabel = NSTextField(labelWithString: "50")
    private let volumeView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 50))
    private let ambientSlider = NSSlider(value: 10, minValue: 1, maxValue: 20, target: nil, action: #selector(ambientLevelChanged(_:)))
    private let levelLabel = NSTextField(labelWithString: "Ambient Level")
    private let levelValueLabel = NSTextField(labelWithString: "10")
    private let ambientLevelView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 54))

    init(client: SonyBluetoothClient) {
        self.client = client
        super.init()

        configureStatusItem()
        configureMenu()

        client.onStateChange = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshMenu() }
        }
        client.onModeChange = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshMenu() }
        }
        client.onBatteryChange = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshMenu() }
        }

        refreshMenu()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Borea")
            button.image?.isTemplate = true
        }
        statusItem.menu = menu
    }

    private func configureMenu() {
        statusHeaderView.onToggle = { [weak self] in
            self?.toggleConnection()
        }
        focusOnVoiceItem.target = self
        modePickerView.delegate = self

        menu.addItem(makeStatusHeaderMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeModePickerMenuItem())
        menu.addItem(ambientTopSeparatorItem)
        menu.addItem(makeSliderMenuItem())
        menu.addItem(focusOnVoiceItem)
        menu.addItem(ambientBottomSeparatorItem)
        menu.addItem(makeVolumeMenuItem())
        menu.addItem(volumeSeparatorItem)
        menu.addItem(NSMenuItem(title: "Quit Borea", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeModePickerMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = modePickerView
        return item
    }

    private func makeStatusHeaderMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = statusHeaderView
        return item
    }

    private func makeVolumeMenuItem() -> NSMenuItem {
        volumeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        volumeLabel.textColor = .secondaryLabelColor
        volumeLabel.frame = NSRect(x: 16, y: 27, width: 190, height: 18)

        volumeValueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        volumeValueLabel.textColor = .secondaryLabelColor
        volumeValueLabel.alignment = .right
        volumeValueLabel.frame = NSRect(x: 250, y: 27, width: 60, height: 18)

        volumeSlider.frame = NSRect(x: 16, y: 4, width: 298, height: 24)
        volumeSlider.target = self
        volumeSlider.numberOfTickMarks = 11
        volumeSlider.allowsTickMarkValuesOnly = false
        volumeView.addSubview(volumeLabel)
        volumeView.addSubview(volumeValueLabel)
        volumeView.addSubview(volumeSlider)

        let item = NSMenuItem()
        item.view = volumeView
        return item
    }

    private func makeSliderMenuItem() -> NSMenuItem {
        levelLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        levelLabel.textColor = .secondaryLabelColor
        levelLabel.frame = NSRect(x: 16, y: 30, width: 190, height: 18)

        levelValueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        levelValueLabel.textColor = .secondaryLabelColor
        levelValueLabel.alignment = .right
        levelValueLabel.frame = NSRect(x: 250, y: 30, width: 60, height: 18)

        ambientSlider.frame = NSRect(x: 16, y: 3, width: 298, height: 24)
        ambientSlider.target = self
        ambientSlider.numberOfTickMarks = 20
        ambientSlider.allowsTickMarkValuesOnly = true
        ambientLevelView.addSubview(levelLabel)
        ambientLevelView.addSubview(levelValueLabel)
        ambientLevelView.addSubview(ambientSlider)

        ambientLevelItem.view = ambientLevelView
        return ambientLevelItem
    }

    private func refreshMenu() {
        let connected = client.connectionState == .connected
        let busy = client.connectionState == .connecting

        statusHeaderView.update(isConnected: connected, isBusy: busy, batteryReport: client.batteryReport)
        let volume = VolumeController.currentVolume()
        volumeSlider.integerValue = volume
        volumeValueLabel.stringValue = "\(volume)"
        modePickerView.isPickerEnabled = connected
        modePickerView.selectedMode = client.mode
        modePickerView.isSwitching = client.isSwitchingMode
        let ambientVisible = client.mode?.isAmbient ?? false
        ambientTopSeparatorItem.isHidden = false
        ambientLevelItem.isHidden = !ambientVisible
        focusOnVoiceItem.isHidden = !ambientVisible
        ambientBottomSeparatorItem.isHidden = !ambientVisible
        volumeSeparatorItem.isHidden = false
        ambientSlider.isEnabled = connected
        focusOnVoiceItem.isEnabled = connected && ambientVisible
        focusOnVoiceItem.state = client.focusOnVoice ? .on : .off

        ambientSlider.integerValue = client.ambientLevel
        levelValueLabel.stringValue = "\(client.ambientLevel)"
    }

    @objc private func toggleConnection() {
        if client.connectionState == .connected || client.connectionState == .connecting {
            client.disconnect()
        } else {
            client.connect()
        }
        refreshMenu()
    }

    @objc private func toggleFocusOnVoice() {
        client.setFocusOnVoice(!client.focusOnVoice)
    }

    @objc private func ambientLevelChanged(_ sender: NSSlider) {
        let level = max(1, min(20, sender.integerValue))
        client.setAmbientLevel(level)
        refreshMenu()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        let volume = min(100, max(0, sender.integerValue))
        VolumeController.setVolume(volume)
        volumeValueLabel.stringValue = "\(volume)"
    }
}

private final class StatusHeaderView: NSView {
    var onToggle: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Borea")
    private let detailLabel = NSTextField(labelWithString: "Disconnected")
    private let batteryIconView = NSImageView(frame: NSRect(x: 92, y: 27, width: 15, height: 13))
    private let batteryLabel = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 48))
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }

    private func setup() {
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 16, y: 7, width: 200, height: 18)
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 16, y: 26, width: 78, height: 17)
        addSubview(detailLabel)

        batteryIconView.imageScaling = .scaleProportionallyDown
        batteryIconView.contentTintColor = .secondaryLabelColor
        batteryIconView.isHidden = true
        addSubview(batteryIconView)

        batteryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        batteryLabel.textColor = .secondaryLabelColor
        batteryLabel.frame = NSRect(x: 110, y: 26, width: 54, height: 17)
        batteryLabel.isHidden = true
        addSubview(batteryLabel)

        toggle.frame = NSRect(x: 252, y: 8, width: 58, height: 32)
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        addSubview(toggle)
    }

    func update(isConnected: Bool, isBusy: Bool, batteryReport: BatteryReport?) {
        titleLabel.stringValue = isConnected ? "WH-1000XM4" : "Borea"
        if isBusy {
            detailLabel.stringValue = "Connecting..."
            detailLabel.frame.size.width = 220
            batteryIconView.isHidden = true
            batteryLabel.isHidden = true
        } else if isConnected {
            detailLabel.stringValue = "Connected"
            detailLabel.frame.size.width = 78
            if let batteryReport {
                batteryIconView.image = NSImage(systemSymbolName: batterySymbolName(for: batteryReport.percentage), accessibilityDescription: "Battery")
                batteryIconView.isHidden = false
                batteryLabel.stringValue = "\(batteryReport.percentage)%"
                batteryLabel.isHidden = false
            } else {
                batteryIconView.isHidden = true
                batteryLabel.isHidden = true
            }
        } else {
            detailLabel.stringValue = "Disconnected"
            detailLabel.frame.size.width = 220
            batteryIconView.isHidden = true
            batteryLabel.isHidden = true
        }

        toggle.isEnabled = !isBusy
        toggle.state = isConnected || isBusy ? .on : .off
    }

    @objc private func toggleChanged() {
        onToggle?()
    }

    private func batterySymbolName(for percentage: Int) -> String {
        switch percentage {
        case 75...100:
            return "battery.100"
        case 40..<75:
            return "battery.75"
        case 15..<40:
            return "battery.25"
        default:
            return "battery.0"
        }
    }
}

extension MenuController: ModePickerViewDelegate {
    func modePickerView(_ view: ModePickerView, didSelect mode: SonyMode) {
        switch mode {
        case .noiseCancelling:
            client.setMode(.noiseCancelling)
        case .ambient:
            client.setMode(.ambient(level: ambientSlider.integerValue, focusOnVoice: client.focusOnVoice))
        case .off:
            client.setMode(.off)
        }
        refreshMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshMenu()
        }
    }
}
