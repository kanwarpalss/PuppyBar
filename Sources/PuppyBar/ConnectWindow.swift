import AppKit

/// Where the Claude token gets pasted. Deliberately the only place a secret is typed:
/// the value goes straight from this secure field into PuppyBar's Keychain entry.
final class ConnectWindowController: NSWindowController, NSWindowDelegate {

    private let field = NSSecureTextField()
    private let status = NSTextField(labelWithString: "")
    private let onSaved: () -> Void

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Connect Claude"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let paw = NSImageView(image: PawIcon.filled(size: 40, color: .controlAccentColor))
        paw.frame = NSRect(x: 24, y: 232, width: 40, height: 40)
        content.addSubview(paw)

        let title = NSTextField(labelWithString: "Paste your Claude token")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 76, y: 246, width: 360, height: 22)
        content.addSubview(title)

        let help = NSTextField(wrappingLabelWithString: """
        1. Open Terminal and run:  claude setup-token
        2. Sign in when the browser opens, then copy the token it prints.
        3. Paste it below.

        The token is stored only in your macOS Keychain, under the service “PuppyBar”. \
        It is sent to api.anthropic.com and nowhere else.
        """)
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 24, y: 122, width: 412, height: 112)
        content.addSubview(help)

        field.placeholderString = "sk-ant-oat…"
        field.frame = NSRect(x: 24, y: 84, width: 412, height: 26)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        content.addSubview(field)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 24, y: 56, width: 412, height: 18)
        content.addSubview(status)

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 344, y: 16, width: 92, height: 30)
        content.addSubview(save)

        let remove = NSButton(title: "Remove Token", target: self, action: #selector(removeToken))
        remove.bezelStyle = .rounded
        remove.frame = NSRect(x: 24, y: 16, width: 130, height: 30)
        content.addSubview(remove)
    }

    @objc private func save() {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            show("Nothing to save — the field is empty.", ok: false)
            return
        }
        // Cheap sanity check so an obviously-wrong paste is caught before a network round trip.
        guard value.count > 20, !value.contains(" ") else {
            show("That doesn't look like a token. Copy the whole line `claude setup-token` printed.", ok: false)
            return
        }
        if Keychain.write(account: Keychain.anthropicAccount, value: value) {
            field.stringValue = ""
            show("Saved to Keychain. Checking your usage…", ok: true)
            onSaved()
        } else {
            show("macOS refused to write to the Keychain.", ok: false)
        }
    }

    @objc private func removeToken() {
        if Keychain.delete(account: Keychain.anthropicAccount) {
            show("Token removed from Keychain.", ok: true)
            onSaved()
        } else {
            show("Couldn't remove the token.", ok: false)
        }
    }

    private func show(_ message: String, ok: Bool) {
        status.stringValue = message
        status.textColor = ok ? .systemGreen : .systemRed
    }
}
