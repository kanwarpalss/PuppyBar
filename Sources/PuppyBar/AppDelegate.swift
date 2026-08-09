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

    /// The menu bar shows the single most urgent number across everything.
    private func updateStatusTitle() {
        let ordered = providers.compactMap { snapshots[$0.name] }
        guard let title = MenuText.statusTitle(ordered) else {
            statusItem.button?.title = ""
            statusItem.button?.toolTip = "PuppyBar — not connected yet"
            return
        }
        statusItem.button?.title = " " + title
        statusItem.button?.toolTip = "PuppyBar — highest usage across Claude and ChatGPT"
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
                menu.addItem(row.secondary == nil ? detailItem(row.primary, wrap: true) : rowItem(row))
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
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
        ])
        return item
    }

    private func rowItem(_ row: MenuText.Row) -> NSMenuItem {
        let line1 = row.primary
        let line2 = row.secondary ?? ""

        let item = NSMenuItem(title: line1, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let text = NSMutableAttributedString(string: line1 + "\n" + line2)
        text.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ], range: NSRange(location: 0, length: line1.count))
        text.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ], range: NSRange(location: line1.count + 1, length: line2.count))
        item.attributedTitle = text
        return item
    }

    private func detailItem(_ text: String, wrap: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        if wrap { paragraph.maximumLineHeight = 15 }
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
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
