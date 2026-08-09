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
    private var isMenuOpen = false

    /// Background poll interval. Each Claude poll costs ~1 Haiku token, so we stay gentle.
    private let pollInterval: TimeInterval = 300
    /// Reopening the menu within this window reuses cached data instead of re-fetching,
    /// so the dropdown doesn't visibly resize on every single open.
    private let staleAfter: TimeInterval = 20

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenuForTextEditing()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = PawIcon.image()
        statusItem.button?.imagePosition = .imageOnly // no reserved space for a title we never set
        statusItem.button?.toolTip = "PuppyBar — AI usage at a glance"

        for provider in providers {
            snapshots[provider.name] = ProviderSnapshot(name: provider.name, state: .idle, fetchedAt: nil)
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        performRefresh(forceRebuild: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // A background tick shouldn't resize the dropdown while it's open on screen;
            // the numbers will simply be current the next time it's opened.
            self?.performRefresh(forceRebuild: false)
        }
    }

    /// Menu-bar-only apps have no visible menu bar of their own, so without this, macOS
    /// has nowhere to register ⌘C / ⌘V / ⌘A — they silently do nothing in the Connect
    /// Claude field. The menu itself is never shown; it exists purely so AppKit can route
    /// these key equivalents to whatever text field is focused.
    private func installMainMenuForTextEditing() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit PuppyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        rebuildMenu() // paint instantly from whatever we already have — no network wait
        if isAnyProviderStale() {
            performRefresh(forceRebuild: true)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func isAnyProviderStale() -> Bool {
        providers.contains { provider in
            guard let fetchedAt = snapshots[provider.name]?.fetchedAt else { return true }
            return Date().timeIntervalSince(fetchedAt) > staleAfter
        }
    }

    // MARK: - Polling

    @objc private func refreshNow() {
        performRefresh(forceRebuild: true)
    }

    private func performRefresh(forceRebuild: Bool) {
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
            guard let self else { return }
            self.isRefreshing = false
            self.updateStatusTitle()
            // A refresh the user asked for (open, "Refresh Now") always repaints. A quiet
            // background tick only repaints if the menu isn't open to look at right now —
            // otherwise the rows would resize mid-glance.
            if forceRebuild || !self.isMenuOpen {
                self.rebuildMenu()
            }
        }
    }

    /// Just the paw — no percentage. Three windows matter equally, so no single number
    /// stands in for all of them; the tooltip carries all three for a no-click peek.
    private func updateStatusTitle() {
        let ordered = providers.compactMap { snapshots[$0.name] }
        statusItem.button?.toolTip = MenuText.tooltip(ordered)
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        for provider in providers {
            let snapshot = snapshots[provider.name] ?? ProviderSnapshot(name: provider.name, state: .idle, fetchedAt: nil)
            let sectionItem = NSMenuItem()
            sectionItem.view = ProviderSectionView(snapshot: snapshot, now: now)
            menu.addItem(sectionItem)
            menu.addItem(.separator())
        }

        menu.addItem(footnote("Updated \(Format.relativeAge(latestFetch(), now: now))"))

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
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
        menu.addItem(NSMenuItem(title: "Quit PuppyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func latestFetch() -> Date? {
        snapshots.values.compactMap(\.fetchedAt).max()
    }

    /// A true footnote — native dimmed style is the correct, expected look here,
    /// unlike the provider content above, which the user actually needs to read.
    private func footnote(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func showConnect() {
        if connectWindow == nil {
            connectWindow = ConnectWindowController { [weak self] in
                self?.performRefresh(forceRebuild: true)
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
