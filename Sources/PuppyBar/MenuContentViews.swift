import AppKit
import PuppyBarCore

/// One provider's block of content (header, windows or a message), used as an
/// NSMenuItem's custom view.
///
/// Why a custom view instead of NSMenuItem.attributedTitle with embedded "\n":
/// AppKit's own height calculation for multi-line attributedTitle text is unreliable —
/// it's the direct cause of the dropdown resizing oddly and leaving blank space below
/// the last item. A view we lay out ourselves has a frame we control exactly, so the
/// menu's size always matches its real content.
final class ProviderSectionView: NSView {

    static let width: CGFloat = 300
    private static let hPad: CGFloat = 16

    override var isFlipped: Bool { true } // y grows downward, i.e. normal reading order

    init(snapshot: ProviderSnapshot, now: Date) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
        frame.size.height = build(snapshot: snapshot, now: now)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build(snapshot: ProviderSnapshot, now: Date) -> CGFloat {
        let hPad = Self.hPad
        let contentWidth = Self.width - hPad * 2
        var y: CGFloat = 10

        var headerText = snapshot.name.uppercased()
        if case let .ok(plan, _, _) = snapshot.state, let plan {
            headerText += "  ·  \(plan.uppercased())"
        }
        addSubview(trackedLabel(headerText, font: .systemFont(ofSize: 11, weight: .semibold),
                                color: .secondaryLabelColor, x: hPad, y: y, width: contentWidth, height: 14))
        y += 14 + 10

        switch snapshot.state {
        case .idle:
            addSubview(plainLabel("Checking…", font: .systemFont(ofSize: 12), color: .tertiaryLabelColor,
                                  x: hPad, y: y, width: contentWidth, height: 16))
            y += 16 + 10

        case .notConnected(let message), .failed(let message):
            let field = wrappingLabel(message, font: .systemFont(ofSize: 12), color: .labelColor,
                                      x: hPad, y: y, width: contentWidth)
            addSubview(field)
            y += field.frame.height + 10

        case .ok(_, let windows, let rateLimited):
            if rateLimited {
                addSubview(plainLabel("Limit reached right now", font: .systemFont(ofSize: 12, weight: .semibold),
                                      color: .systemRed, x: hPad, y: y, width: contentWidth, height: 16))
                y += 16 + 8
            }
            if windows.isEmpty {
                addSubview(plainLabel("No usage windows reported.", font: .systemFont(ofSize: 12),
                                      color: .secondaryLabelColor, x: hPad, y: y, width: contentWidth, height: 16))
                y += 16 + 10
            }
            for (index, window) in windows.enumerated() {
                y = addWindowRow(window, top: y, hPad: hPad, contentWidth: contentWidth, now: now)
                y += (index < windows.count - 1) ? 14 : 10
            }
        }

        return y
    }

    private func addWindowRow(_ window: Window, top: CGFloat, hPad: CGFloat,
                               contentWidth: CGFloat, now: Date) -> CGFloat {
        var y = top
        let tint = color(for: Severity.forUsed(window.usedPercent))
        let nameWidth = contentWidth * 0.58
        let percentWidth = contentWidth - nameWidth

        addSubview(plainLabel(window.label, font: .systemFont(ofSize: 12.5, weight: .medium), color: .labelColor,
                              x: hPad, y: y, width: nameWidth, height: 17))

        let percentField = plainLabel("\(Format.percent(window.remainingPercent)) left",
                                      font: .systemFont(ofSize: 12.5, weight: .semibold), color: tint,
                                      x: hPad + nameWidth, y: y, width: percentWidth, height: 17)
        percentField.alignment = .right
        addSubview(percentField)
        y += 17 + 6

        let bar = ProgressBarView(percent: window.usedPercent, color: tint)
        bar.frame = NSRect(x: hPad, y: y, width: contentWidth, height: 6)
        addSubview(bar)
        y += 6 + 6

        addSubview(plainLabel(Format.resetPhrase(window.resetsAt, now: now), font: .systemFont(ofSize: 10.5),
                              color: .secondaryLabelColor, x: hPad, y: y, width: contentWidth, height: 14))
        y += 14

        return y
    }

    private func color(for severity: Severity) -> NSColor {
        switch severity {
        case .calm: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func plainLabel(_ text: String, font: NSFont, color: NSColor,
                            x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        return field
    }

    private func trackedLabel(_ text: String, font: NSFont, color: NSColor,
                              x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSTextField {
        let field = plainLabel(text, font: font, color: color, x: x, y: y, width: width, height: height)
        field.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .kern: 0.6,
        ])
        return field
    }

    /// Height is computed from the actual text metrics rather than left to `sizeToFit`,
    /// which needs Auto Layout constraints to behave — we're doing plain frame layout here.
    private func wrappingLabel(_ text: String, font: NSFont, color: NSColor,
                               x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        field.frame = NSRect(x: x, y: y, width: width, height: ceil(bounding.height) + 2)
        return field
    }
}

/// A drawn, rounded progress track. Crisper at any scale than a row of unicode block
/// characters, and immune to the font-metric drift that made the old bars uneven.
final class ProgressBarView: NSView {
    private let percent: Double
    private let tint: NSColor

    init(percent: Double, color: NSColor) {
        self.percent = percent
        self.tint = color
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let clamped = min(max(percent, 0), 100)
        guard clamped > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(clamped / 100))
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        tint.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
