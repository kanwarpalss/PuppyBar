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
    private var menuNeedsRebuild = false
    private weak var menuHeader: MenuHeaderView?
    private weak var launchAtLoginRow: MenuActionRowView?

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

        performRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // A background tick shouldn't resize the dropdown while it's open on screen;
            // the numbers will simply be current the next time it's opened.
            self?.performRefresh()
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
        // The menu already reflects the most recent closed-state refresh. Rebuilding here
        // can visibly change its height while macOS is opening it, so never do that.
        if isAnyProviderStale() {
            performRefresh()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if menuNeedsRebuild {
            rebuildMenu()
            menuNeedsRebuild = false
        }
    }

    private func isAnyProviderStale() -> Bool {
        providers.contains { provider in
            guard let fetchedAt = snapshots[provider.name]?.fetchedAt else { return true }
            return Date().timeIntervalSince(fetchedAt) > staleAfter
        }
    }

    // MARK: - Polling

    @objc private func refreshNow() {
        performRefresh()
    }

    @discardableResult
    private func performRefresh() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        menuHeader?.setRefreshing(true)

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
            self.menuHeader?.showRefreshAge(self.latestFetch(), now: Date())
            // Never change a menu's frames while it is on screen. Fresh data is staged and
            // painted immediately after close, ready for the next opening.
            if MenuUpdatePolicy.shouldRebuildAfterRefresh(menuIsOpen: self.isMenuOpen) {
                self.rebuildMenu()
            } else {
                self.menuNeedsRebuild = true
            }
        }
        return true
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

        let header = MenuHeaderView(refreshedAt: latestFetch(), now: now) { [weak self] in
            self?.refreshNow()
        }
        menuHeader = header
        menu.addItem(item(for: header))
        menu.addItem(.separator())

        for provider in providers {
            let snapshot = snapshots[provider.name] ?? ProviderSnapshot(name: provider.name, state: .idle, fetchedAt: nil)
            let sectionItem = NSMenuItem()
            let reconnect = reconnectAction(for: snapshot)
            sectionItem.view = ProviderSectionView(snapshot: snapshot, now: now,
                                                   reconnectTitle: reconnect?.title,
                                                   onReconnect: reconnect?.action)
            menu.addItem(sectionItem)
        }

        menu.addItem(.separator())

        let loginRow = MenuActionRowView(title: "Launch at Login",
                                         isChecked: SMAppService.mainApp.status == .enabled) { [weak self] in
            self?.toggleLaunchAtLogin()
        }
        launchAtLoginRow = loginRow
        menu.addItem(item(for: loginRow))

        let quitRow = MenuActionRowView(title: "Quit PuppyBar") {
            NSApp.terminate(nil)
        }
        menu.addItem(item(for: quitRow))
    }

    private func item(for view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func reconnectAction(for snapshot: ProviderSnapshot) -> (title: String, action: () -> Void)? {
        guard case .notConnected = snapshot.state else { return nil }
        switch snapshot.name {
        case "Claude":
            return ("Reconnect Claude…", { [weak self] in self?.showConnect() })
        case "ChatGPT":
            return ("Reconnect ChatGPT…", { [weak self] in self?.reconnectChatGPT() })
        default:
            return nil
        }
    }

    private func latestFetch() -> Date? {
        snapshots.values.compactMap(\.fetchedAt).max()
    }

    // MARK: - Actions

    @objc private func showConnect() {
        if connectWindow == nil {
            connectWindow = ConnectWindowController { [weak self] in
                self?.performRefresh()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        connectWindow?.showWindow(nil)
        connectWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func reconnectChatGPT() {
        if let chatGPT = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: chatGPT, configuration: configuration) { _, error in
                if let error { self.showChatGPTReconnectHelp(error.localizedDescription) }
            }
        } else {
            showChatGPTReconnectHelp(nil)
        }
    }

    private func showChatGPTReconnectHelp(_ detail: String?) {
        let alert = NSAlert()
        alert.messageText = "Reconnect ChatGPT"
        alert.informativeText = "Open the ChatGPT or Codex app and sign in. PuppyBar will use that refreshed connection the next time it checks usage."
            + (detail.map { "\n\n\($0)" } ?? "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
        launchAtLoginRow?.isChecked = SMAppService.mainApp.status == .enabled
    }
}
