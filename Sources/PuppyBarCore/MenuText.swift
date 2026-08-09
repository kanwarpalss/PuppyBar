import Foundation

/// Every line PuppyBar shows, built in exactly one place.
/// The menu and the `--dump` diagnostic both render from here, so they cannot drift. (ARCH-04)
public enum MenuText {

    public struct Row: Equatable {
        public let primary: String
        public let secondary: String?
        public init(primary: String, secondary: String? = nil) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public struct Section: Equatable {
        public let header: String
        public let rows: [Row]
    }

    /// Width the window label is padded to, so the bars line up in a column.
    static let labelWidth = 17

    public static func section(for snapshot: ProviderSnapshot, now: Date = Date()) -> Section {
        var header = snapshot.name.uppercased()
        if case let .ok(plan, _, _) = snapshot.state, let plan { header += " · \(plan)" }

        var rows: [Row] = []
        switch snapshot.state {
        case .idle:
            rows.append(Row(primary: "Checking…"))
        case .notConnected(let message), .failed(let message):
            rows.append(Row(primary: message))
        case .ok(_, let windows, let rateLimited):
            if rateLimited {
                rows.append(Row(primary: "⛔️ Limit reached right now."))
            }
            for window in windows {
                rows.append(row(for: window, now: now))
            }
            if windows.isEmpty {
                rows.append(Row(primary: "No usage windows reported."))
            }
        }
        return Section(header: header, rows: rows)
    }

    public static func row(for window: Window, now: Date = Date()) -> Row {
        let label = window.label.count >= labelWidth
            ? window.label
            : window.label + String(repeating: " ", count: labelWidth - window.label.count)
        let primary = "\(Severity.forUsed(window.usedPercent).dot)  \(label)"
            + "\(Format.bar(usedPercent: window.usedPercent))  "
            + "\(Format.percent(window.remainingPercent)) left"
        let secondary = "        \(Format.resetPhrase(window.resetsAt, now: now))"
        return Row(primary: primary, secondary: secondary)
    }

    /// Single worst percentage across everything. Used by `--dump` and the tooltip.
    /// Deliberately NOT shown in the menu bar: one number can't stand in for three
    /// windows, and a summary you have to click anyway is just clutter.
    public static func statusTitle(_ snapshots: [ProviderSnapshot]) -> String? {
        guard let worst = snapshots.compactMap(\.worstUsedPercent).max() else { return nil }
        return Format.percent(worst)
    }

    /// Hover text: all three windows on separate lines, so a hover answers the
    /// question without a click.
    public static func tooltip(_ snapshots: [ProviderSnapshot]) -> String {
        var lines: [String] = []
        for snapshot in snapshots {
            switch snapshot.state {
            case .ok(_, let windows, _) where !windows.isEmpty:
                for window in windows {
                    lines.append("\(snapshot.name) \(window.label): \(Format.percent(window.remainingPercent)) left")
                }
            case .notConnected:
                lines.append("\(snapshot.name): not connected")
            case .failed:
                lines.append("\(snapshot.name): couldn't check")
            default:
                lines.append("\(snapshot.name): checking…")
            }
        }
        return lines.isEmpty ? "PuppyBar" : lines.joined(separator: "\n")
    }
}
