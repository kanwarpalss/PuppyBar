import AppKit
import PuppyBarCore

/// Command-line escape hatches. Not part of the UI, but they make the app
/// checkable without squinting at a menu bar.
enum Diagnostics {

    /// Polls every provider once and prints the exact menu contents.
    static func dumpAndExit() -> Never {
        let providers: [UsageProvider] = [AnthropicProvider(), OpenAIProvider()]
        var snapshots: [ProviderSnapshot] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.fetch { state in
                lock.lock()
                snapshots.append(ProviderSnapshot(name: provider.name, state: state, fetchedAt: Date()))
                lock.unlock()
                group.leave()
            }
        }

        if group.wait(timeout: .now() + 30) == .timedOut {
            print("Timed out waiting for providers.")
            exit(1)
        }

        // Keep provider order stable regardless of which response landed first.
        let order = providers.map(\.name)
        snapshots.sort { (order.firstIndex(of: $0.name) ?? 0) < (order.firstIndex(of: $1.name) ?? 0) }

        let now = Date()
        print("")
        print("  🐾 PuppyBar   \(MenuText.statusTitle(snapshots) ?? "—")")
        print("  " + String(repeating: "─", count: 52))
        for snapshot in snapshots {
            let section = MenuText.section(for: snapshot, now: now)
            print("  \(section.header)")
            for row in section.rows {
                print("  \(row.primary)")
                if let secondary = row.secondary { print("  \(secondary)") }
            }
            print("  " + String(repeating: "─", count: 52))
        }
        print("  Updated \(Format.relativeAge(now, now: now))")
        print("")

        // Exit non-zero if nothing at all could be read, so scripts can gate on it.
        let anyData = snapshots.contains { $0.worstUsedPercent != nil }
        exit(anyData ? 0 : 1)
    }

    /// Renders the paw to a PNG so the artwork can actually be looked at.
    static func writePaw(to path: String, size: CGFloat = 256) {
        let image = PawIcon.filled(size: size, color: .black)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Couldn't render the paw.")
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path)")
        } catch {
            print("Couldn't write \(path): \(error.localizedDescription)")
            exit(1)
        }
    }
}
