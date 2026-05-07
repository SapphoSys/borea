import AppKit

protocol ModePickerViewDelegate: AnyObject {
    func modePickerView(_ view: ModePickerView, didSelect mode: SonyMode)
}

final class ModePickerView: NSView {
    weak var delegate: ModePickerViewDelegate?

    var selectedMode: SonyMode? {
        didSet { needsDisplay = true }
    }

    var isPickerEnabled = false {
        didSet { needsDisplay = true }
    }

    var isSwitching = false {
        didSet { needsDisplay = true }
    }

    private let titleLabel = NSTextField(labelWithString: "Mode")
    private let segments: [Segment] = [
        Segment(mode: .noiseCancelling, title: "Noise", symbolName: "headphones"),
        Segment(mode: .ambient(level: 10, focusOnVoice: false), title: "Ambient", symbolName: "ear"),
        Segment(mode: .off, title: "Off", symbolName: "power")
    ]

    private var modeTrackingAreas: [NSTrackingArea] = []
    private var hoveredIndex: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 70))
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
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: 16, y: 7, width: 180, height: 18)
        addSubview(titleLabel)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in modeTrackingAreas {
            removeTrackingArea(area)
        }
        modeTrackingAreas.removeAll()

        for (index, rect) in segmentRects().enumerated() {
            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["index": index]
            )
            addTrackingArea(area)
            modeTrackingAreas.append(area)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, segment) in segments.enumerated() {
            draw(segment: segment, index: index, rect: segmentRects()[index])
        }

        if isSwitching {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            NSAttributedString(string: "Switching...", attributes: attributes)
                .draw(at: NSPoint(x: 236, y: 8))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hoveredIndex = event.trackingArea?.userInfo?["index"] as? Int
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isPickerEnabled, !isSwitching else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = segmentRects().firstIndex(where: { $0.contains(point) }) else { return }
        delegate?.modePickerView(self, didSelect: segments[index].mode)
    }

    private func segmentRects() -> [NSRect] {
        let row = NSRect(x: 12, y: 28, width: 306, height: 34)
        let gap: CGFloat = 8
        let widths: [CGFloat] = [92, 118, 80]
        var x = row.minX

        return widths.map { width in
            defer { x += width + gap }
            return NSRect(x: x, y: row.minY, width: width, height: row.height)
        }
    }

    private func draw(segment: Segment, index: Int, rect: NSRect) {
        let selected = isSelected(segment.mode)
        let hovered = hoveredIndex == index && isPickerEnabled && !isSwitching
        let alpha: CGFloat = isPickerEnabled ? 1 : 0.45
        let contentAlpha: CGFloat = isSwitching && !selected ? 0.58 : alpha
        let backgroundRect = rect.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: backgroundRect, xRadius: 12, yRadius: 12)

        if selected {
            NSColor.systemOrange.withAlphaComponent(isSwitching ? 0.82 : alpha).setFill()
            path.fill()
            if isSwitching {
                NSColor.white.withAlphaComponent(0.26).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        } else if hovered {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }

        let contentColor: NSColor = selected ? .white : (isPickerEnabled ? .labelColor : .disabledControlTextColor)
        let symbolRect = NSRect(x: rect.minX + 14, y: rect.minY + 8, width: 18, height: 18)
        if let image = NSImage(systemSymbolName: segment.symbolName, accessibilityDescription: segment.title) {
            let configuredImage = image.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold)) ?? image
            let tintedImage = configuredImage.tinted(with: contentColor.withAlphaComponent(contentAlpha))
            tintedImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        contentColor.set()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
            .foregroundColor: contentColor.withAlphaComponent(contentAlpha)
        ]
        let attributedTitle = NSAttributedString(string: segment.title, attributes: attributes)
        let titleSize = attributedTitle.size()
        let titlePoint = NSPoint(
            x: rect.minX + 41,
            y: rect.midY - titleSize.height / 2
        )
        attributedTitle.draw(at: titlePoint)
    }

    private func isSelected(_ mode: SonyMode) -> Bool {
        switch (selectedMode, mode) {
        case (.noiseCancelling, .noiseCancelling):
            return true
        case (.ambient, .ambient):
            return true
        case (.off, .off):
            return true
        default:
            return false
        }
    }
}

private struct Segment {
    let mode: SonyMode
    let title: String
    let symbolName: String
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect, from: rect, operation: .sourceOver, fraction: 1)
        color.set()
        rect.fill(using: .sourceAtop)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
