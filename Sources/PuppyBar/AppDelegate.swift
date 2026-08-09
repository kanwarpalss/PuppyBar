import AppKit
import ServiceManagement
import PuppyBarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    private var connectWindow: ConnectWindowController?

    private let providers: [UsageProvider] = [AnthropicProvider(), OpenAIProvider()]
    private var snapshots: [String: ProviderSnapshot] = [:]
    private var isRefreshing = false

    /// Background poll interval. Each Claude poll costs ~1 Haiku token, so we stay gentle;
    /// opening the menu always triggers a fresh fetch anyway.
    private let pollInterval: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = PawIcon.image()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "PuppyBar — AI usage at a glance"

        for provider in providers {
            snapshots[provider.name] = ProviderSnapshot(name: provider.name, state: .idle, fetchedAt: nil)
        }

        menu.delegate = self
        // macOS dims disabled items regardless of the colours we set, which made the
        // provider headings look greyed out. Managing enablement ourselves keeps the
        // text at full strength.
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuildMenu()

        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // Fresh numbers the moment the paws are clicked.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        refresh()
    }

    // MARK: - Polling

    @objc func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.fetch { [weak self] state in
                DispatchQueue.main.async {
                    self?.snapshots[provider.name] = ProviderSnapshot(
                        name: provider.name, state: state, fetchedAt: Date())
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isRefreshing = false
            self?.rebuildMenu()
            self?.updateStatusTitle()
        }
    }

    /// Just the paw. No percentage: there are three windows worth knowing and no single
    /// number represents them, so the menu bar stays clean and the detail lives one click away.
    /// The hover tooltip carries all three lines for a no-click peek.
    private func updateStatusTitle() {
        let ordered = providers.compactMap { snapshots[$0.name] }
        statusItem.button?.title = ""
        statusItem.button?.toolTip = MenuText.tooltip(ordered)
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        for provider in providers {
            let snapshot = snapshots[provider.name] ?? ProviderSnapshot(name: provider.name, state: .idle, fetchedAt: nil)
            let section = MenuText.section(for: snapshot, now: now)
            menu.addItem(headerItem(title: section.header))
            for row in section.rows {
                menu.addItem(row.secondary == nil
                    ? detailItem(row.primary, wrap: true, prominent: true)
                    : rowItem(row))
            }
            menu.addItem(.separator())
        }

        menu.addItem(detailItem("Updated \(Format.relativeAge(latestFetch(), now: now))"))

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let connectTitle = Keychain.read(account: Keychain.anthropicAccount) == nil
            ? "Connect Claude…" : "Reconnect Claude…"
        let connectItem = NSMenuItem(title: connectTitle, action: #selector(showConnect), keyEquivalent: "")
        connectItem.target = self
        menu.addItem(connectItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit PuppyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func latestFetch() -> Date? {
        snapshots.values.compactMap(\.fetchedAt).max()
    }

    private func headerItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true // full-strength text; nil action means it still does nothing
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .kern: 0.6,
        ])
        return item
    }

    private func rowItem(_ row: MenuText.Row) -> NSMenuItem {
        let line1 = row.primary
        let line2 = row.secondary ?? ""

        let item = NSMenuItem(title: line1, action: nil, keyEquivalent: "")
        item.isEnabled = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 1
        let text = NSMutableAttributedString(string: line1 + "\n" + line2)
        // NSRange works in UTF-16 units; line1 contains emoji, so .count would misalign
        // the ranges and colour the wrong characters.
        let split = (line1 as NSString).length
        text.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ], range: NSRange(location: 0, length: split))
        text.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ], range: NSRange(location: split + 1, length: (line2 as NSString).length))
        item.attributedTitle = text
        return item
    }

    /// `prominent` is for things the user must actually read (e.g. "Not connected").
    /// Quiet footnotes like "Updated 4s ago" stay secondary.
    private func detailItem(_ text: String, wrap: Bool = false, prominent: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: prominent ? 12.5 : 11,
                                     weight: prominent ? .medium : .regular),
            .foregroundColor: prominent ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        return item
    }

    // MARK: - Actions

    @objc private func showConnect() {
        if connectWindow == nil {
            connectWindow = ConnectWindowController { [weak self] in
                self?.refresh()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        connectWindow?.showWindow(nil)
        connectWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Never fail silently. (DEBUG-01)
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nThis usually means PuppyBar.app isn't in /Applications yet."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        rebuildMenu()
    }
}
