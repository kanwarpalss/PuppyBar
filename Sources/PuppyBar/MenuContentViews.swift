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

    static let width: CGFloat = 278
    private static let hPad: CGFloat = 14

    override var isFlipped: Bool { true } // y grows downward, i.e. normal reading order

    init(snapshot: ProviderSnapshot, now: Date, reconnectTitle: String? = nil,
         onReconnect: (() -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
        frame.size.height = build(snapshot: snapshot, now: now, reconnectTitle: reconnectTitle,
                                  onReconnect: onReconnect)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build(snapshot: ProviderSnapshot, now: Date, reconnectTitle: String?,
                       onReconnect: (() -> Void)?) -> CGFloat {
        let hPad = Self.hPad
        let contentWidth = Self.width - hPad * 2
        var y: CGFloat = 10

        addSubview(plainLabel(snapshot.name, font: .systemFont(ofSize: 14, weight: .semibold),
                              color: providerHeadingColor(snapshot.name), x: hPad, y: y,
                              width: contentWidth, height: 18))
        y += 18 + 7

        switch snapshot.state {
        case .idle:
            addSubview(plainLabel("Checking…", font: .systemFont(ofSize: 11.5), color: .tertiaryLabelColor,
                                  x: hPad, y: y, width: contentWidth, height: 15))
            y += 15 + 7

        case .notConnected(let message):
            let field = wrappingLabel(message, font: .systemFont(ofSize: 12), color: .labelColor,
                                      x: hPad, y: y, width: contentWidth)
            addSubview(field)
            y += field.frame.height + 5
            if let reconnectTitle, let onReconnect {
                let button = MenuActionRowView(title: reconnectTitle, width: contentWidth,
                                               horizontalInset: 0, tint: .controlAccentColor, action: onReconnect)
                button.frame = NSRect(x: hPad, y: y, width: contentWidth, height: MenuActionRowView.height)
                addSubview(button)
                y += MenuActionRowView.height + 7
            } else {
                y += 7
            }

        case .failed(let message):
            let field = wrappingLabel(message, font: .systemFont(ofSize: 12), color: .labelColor,
                                      x: hPad, y: y, width: contentWidth)
            addSubview(field)
            y += field.frame.height + 7

        case .ok(_, let windows, _):
            if windows.isEmpty {
                addSubview(plainLabel("No usage windows reported.", font: .systemFont(ofSize: 12),
                                      color: .secondaryLabelColor, x: hPad, y: y, width: contentWidth, height: 15))
                y += 15 + 8
            }
            for (index, window) in (snapshot.displayedWindows ?? windows).enumerated() {
                y = addWindowRow(window, top: y, hPad: hPad, contentWidth: contentWidth, now: now)
                y += (index < windows.count - 1) ? 8 : 7
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

        addSubview(plainLabel(window.label, font: .systemFont(ofSize: 11.5, weight: .medium), color: .secondaryLabelColor,
                              x: hPad, y: y, width: nameWidth, height: 16))

        let percentField = plainLabel(Format.usageLabel(usedPercent: window.usedPercent),
                                      font: .systemFont(ofSize: 12.5, weight: .semibold), color: tint,
                                      x: hPad + nameWidth, y: y, width: percentWidth, height: 16)
        percentField.alignment = .right
        addSubview(percentField)
        y += 16 + 5

        let bar = ProgressBarView(percent: window.usedPercent, color: tint)
        bar.frame = NSRect(x: hPad, y: y, width: contentWidth, height: 5)
        addSubview(bar)
        y += 5 + 5

        // The reset sentence stays immediately under the usage bar. Its companion period
        // track sits on the right of the same line, without adding another line of text.
        let elapsed = Format.elapsedPeriodPercent(resetsAt: window.resetsAt, duration: window.duration,
                                                  now: now)
        let timeBarWidth: CGFloat = elapsed == nil ? 0 : 58
        let resetWidth = contentWidth - timeBarWidth - (elapsed == nil ? 0 : 8)
        addSubview(plainLabel(Format.resetPhrase(window.resetsAt, now: now), font: .systemFont(ofSize: 9.5),
                              color: .secondaryLabelColor, x: hPad, y: y, width: resetWidth, height: 13))
        if let elapsed {
            // Secondary label is intentionally darker than tertiary label: it should be
            // legible at a glance, while remaining quieter than the coloured usage bar.
            let timeBar = ProgressBarView(percent: elapsed, color: .secondaryLabelColor)
            timeBar.toolTip = "\(Format.percent(elapsed)) of this reset period has elapsed"
            timeBar.frame = NSRect(x: hPad + contentWidth - timeBarWidth, y: y + 4,
                                   width: timeBarWidth, height: 4)
            addSubview(timeBar)
        }
        y += 13

        return y
    }

    private func color(for severity: Severity) -> NSColor {
        switch severity {
        case .calm: return Self.calmGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// Deliberately deeper than system green: calm usage should feel settled, while amber
    /// and red remain reserved for a quota that needs attention.
    private static let calmGreen = NSColor(calibratedRed: 0.09, green: 0.44, blue: 0.24, alpha: 1)

    private func providerHeadingColor(_ name: String) -> NSColor {
        switch name {
        case "Claude": return .systemPurple
        case "ChatGPT": return .systemTeal
        default: return .labelColor
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

/// The fixed-height top strip: a quiet product label, refresh age, and an icon that starts
/// a real provider poll. It replaces the loose “Updated” and “Refresh” footer rows.
final class MenuHeaderView: NSView {
    static let height: CGFloat = 34
    private let refreshAge: NSTextField
    private let reloadButton: MenuReloadButton

    init(refreshedAt: Date?, now: Date, action: @escaping () -> Void) {
        self.refreshAge = NSTextField(labelWithString: Format.refreshedStatus(refreshedAt, now: now))
        self.reloadButton = MenuReloadButton(action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: ProviderSectionView.width, height: Self.height))

        let title = NSTextField(labelWithString: "PuppyBar")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: 8, width: 92, height: 18)
        addSubview(title)

        reloadButton.frame = NSRect(x: ProviderSectionView.width - 38, y: 3, width: 28, height: 28)
        addSubview(reloadButton)

        refreshAge.font = .systemFont(ofSize: 10.5, weight: .medium)
        refreshAge.textColor = .secondaryLabelColor
        refreshAge.alignment = .right
        refreshAge.lineBreakMode = .byTruncatingHead
        refreshAge.frame = NSRect(x: 108, y: 10, width: 124, height: 14)
        addSubview(refreshAge)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setRefreshing(_ refreshing: Bool) {
        refreshAge.stringValue = refreshing ? "Refreshing…" : refreshAge.stringValue
        reloadButton.setEnabled(!refreshing)
    }

    func showRefreshAge(_ date: Date?, now: Date) {
        refreshAge.stringValue = Format.refreshedStatus(date, now: now)
        reloadButton.setEnabled(true)
    }
}

/// Borderless icon controls do not receive AppKit's ordinary menu-item selection style,
/// so this view supplies the same concise hover feedback as the action rows below.
final class MenuReloadButton: NSView {
    private let action: () -> Void
    private let button: NSButton
    private let hoverHighlight = NSView()
    private var hoverTrackingArea: NSTrackingArea?

    init(action: @escaping () -> Void) {
        self.action = action
        self.button = NSButton(title: "", target: nil, action: nil)
        super.init(frame: .zero)

        hoverHighlight.wantsLayer = true
        hoverHighlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        hoverHighlight.layer?.cornerRadius = 5
        hoverHighlight.alphaValue = 0
        addSubview(hoverHighlight)

        button.target = self
        button.action = #selector(activate)
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh usage")
        button.contentTintColor = .controlAccentColor
        button.isBordered = false
        button.focusRingType = .none
        button.toolTip = "Refresh usage"
        button.frame = NSRect(x: 2, y: 2, width: 24, height: 24)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        hoverHighlight.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                          owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) { setHoverHighlight(true) }
    override func mouseExited(with event: NSEvent) { setHoverHighlight(false) }

    func setEnabled(_ enabled: Bool) {
        button.isEnabled = enabled
        button.contentTintColor = enabled ? .controlAccentColor : .secondaryLabelColor
    }

    private func setHoverHighlight(_ highlighted: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            hoverHighlight.animator().alphaValue = highlighted ? 1 : 0
        }
    }

    @objc private func activate() { action() }
}

/// A compact, custom footer row. AppKit draws an NSMenuItem checkmark on the left; this
/// puts Launch at Login's tick on the right where the eye expects a setting's state.
final class MenuActionRowView: NSView {
    static let height: CGFloat = 26

    private let action: () -> Void
    private let checkmark: NSTextField
    private let hoverHighlight = NSView()
    private var hoverTrackingArea: NSTrackingArea?
    var isChecked: Bool {
        didSet { checkmark.isHidden = !isChecked }
    }

    init(title: String, width: CGFloat = ProviderSectionView.width, horizontalInset: CGFloat = 14,
         tint: NSColor = .labelColor,
         isChecked: Bool = false, action: @escaping () -> Void) {
        self.action = action
        self.isChecked = isChecked
        self.checkmark = NSTextField(labelWithString: "✓")
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        hoverHighlight.wantsLayer = true
        hoverHighlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        hoverHighlight.layer?.cornerRadius = 4
        hoverHighlight.alphaValue = 0
        hoverHighlight.frame = bounds
        addSubview(hoverHighlight)

        let button = NSButton(title: title, target: self, action: #selector(activate))
        button.frame = NSRect(x: horizontalInset, y: 0, width: width - horizontalInset, height: Self.height)
        button.isBordered = false
        button.focusRingType = .none
        button.alignment = .left
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.contentTintColor = tint
        addSubview(button)

        checkmark.font = .systemFont(ofSize: 13, weight: .semibold)
        checkmark.textColor = .secondaryLabelColor
        checkmark.alignment = .right
        checkmark.frame = NSRect(x: width - horizontalInset - 12, y: 5, width: 12, height: 16)
        checkmark.isHidden = !isChecked
        addSubview(checkmark)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        hoverHighlight.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                          owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) { setHoverHighlight(true) }
    override func mouseExited(with event: NSEvent) { setHoverHighlight(false) }

    private func setHoverHighlight(_ highlighted: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            hoverHighlight.animator().alphaValue = highlighted ? 1 : 0
        }
    }

    @objc private func activate() { action() }
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
