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

    /// The text beside the paw in the menu bar. nil when there's nothing to report.
    public static func statusTitle(_ snapshots: [ProviderSnapshot]) -> String? {
        guard let worst = snapshots.compactMap(\.worstUsedPercent).max() else { return nil }
        return Format.percent(worst)
    }
}
