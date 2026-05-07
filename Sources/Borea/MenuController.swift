import AppKit

final class MenuController: NSObject {
    private let client: SonyBluetoothClient
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let statusItemView = NSMenuItem(title: "WH-1000XM4 disconnected", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "Battery: --", action: nil, keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "Connect", action: #selector(toggleConnection), keyEquivalent: "c")
    private let focusOnVoiceItem = NSMenuItem(title: "Focus on Voice", action: #selector(toggleFocusOnVoice), keyEquivalent: "v")

    private let modePickerView = ModePickerView()
    private let bottomSeparatorItem = NSMenuItem.separator()
    private let ambientLevelItem = NSMenuItem()
    private let volumeSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: #selector(volumeChanged(_:)))
    private let volumeLabel = NSTextField(labelWithString: "Volume")
    private let volumeValueLabel = NSTextField(labelWithString: "50")
    private let volumeView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 54))
    private let ambientSlider = NSSlider(value: 10, minValue: 1, maxValue: 20, target: nil, action: #selector(ambientLevelChanged(_:)))
    private let levelLabel = NSTextField(labelWithString: "Ambient Level")
    private let levelValueLabel = NSTextField(labelWithString: "10")
    private let ambientLevelView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 54))
    private let focusOnVoiceView = FocusOnVoiceMenuView()

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
        connectionItem.target = self
        modePickerView.delegate = self
        focusOnVoiceView.target = self
        focusOnVoiceView.action = #selector(toggleFocusOnVoice)

        menu.addItem(statusItemView)
        menu.addItem(batteryItem)
        menu.addItem(connectionItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeModePickerMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeVolumeMenuItem())
        menu.addItem(makeSliderMenuItem())
        menu.addItem(makeFocusOnVoiceMenuItem())
        menu.addItem(bottomSeparatorItem)
        menu.addItem(NSMenuItem(title: "Quit Borea", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeModePickerMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = modePickerView
        return item
    }

    private func makeVolumeMenuItem() -> NSMenuItem {
        volumeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        volumeLabel.textColor = .secondaryLabelColor
        volumeLabel.frame = NSRect(x: 16, y: 30, width: 190, height: 18)

        volumeValueLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        volumeValueLabel.textColor = .secondaryLabelColor
        volumeValueLabel.alignment = .right
        volumeValueLabel.frame = NSRect(x: 250, y: 30, width: 60, height: 18)

        volumeSlider.frame = NSRect(x: 16, y: 3, width: 298, height: 24)
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

    private func makeFocusOnVoiceMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = focusOnVoiceView
        return item
    }

    private func refreshMenu() {
        let connected = client.connectionState == .connected
        let busy = client.connectionState == .connecting

        statusItemView.title = connected ? "WH-1000XM4 connected" : "WH-1000XM4 disconnected"
        batteryItem.title = connected ? "Battery: \(client.batteryReport?.title ?? "--")" : "Battery: --"
        batteryItem.isHidden = !connected
        connectionItem.title = connected || busy ? "Disconnect" : "Connect"
        connectionItem.isEnabled = !busy
        let volume = VolumeController.currentVolume()
        volumeSlider.integerValue = volume
        volumeValueLabel.stringValue = "\(volume)"
        modePickerView.isPickerEnabled = connected
        modePickerView.selectedMode = client.mode
        modePickerView.isSwitching = client.isSwitchingMode
        let ambientVisible = client.mode?.isAmbient ?? false
        ambientLevelItem.isHidden = !ambientVisible
        bottomSeparatorItem.isHidden = false
        ambientSlider.isEnabled = connected
        focusOnVoiceView.isControlEnabled = connected && ambientVisible
        focusOnVoiceView.isOn = client.focusOnVoice

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

private final class FocusOnVoiceMenuView: NSView {
    weak var target: AnyObject?
    var action: Selector?

    var isControlEnabled = false {
        didSet { needsDisplay = true }
    }

    var isOn = false {
        didSet { needsDisplay = true }
    }

    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 22))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isControlEnabled, let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let alpha: CGFloat = isControlEnabled ? 1 : 0.42
        if isHovered && isControlEnabled {
            let hoverRect = bounds.insetBy(dx: 8, dy: 1)
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: hoverRect, xRadius: 8, yRadius: 8).fill()
        }

        let textColor = (isControlEnabled ? NSColor.labelColor : .disabledControlTextColor).withAlphaComponent(alpha)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: textColor
        ]
        NSAttributedString(string: "Focus on Voice", attributes: attributes)
            .draw(at: NSPoint(x: 16, y: 2))

        if isOn {
            let checkAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: textColor
            ]
            NSAttributedString(string: "On", attributes: checkAttributes)
                .draw(at: NSPoint(x: 252, y: 2))
        }

        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(alpha)
        ]
        NSAttributedString(string: "⌘ V", attributes: shortcutAttributes)
            .draw(at: NSPoint(x: 286, y: 2))
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
