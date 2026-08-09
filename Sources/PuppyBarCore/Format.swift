import Foundation

/// Single source of truth for every string PuppyBar renders. (ARCH-04)
/// If a percentage or a reset time is formatted anywhere else, it will drift.
public enum Format {

    /// "38%" — always rounded, never "38.0000001%".
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// A 10-cell text bar: "▓▓▓▓░░░░░░". Clamped, so 140% still draws a full bar.
    public static func bar(usedPercent: Double, cells: Int = 10) -> String {
        guard cells > 0 else { return "" }
        let clamped = min(max(usedPercent, 0), 100)
        // Anything above zero shows at least one cell, so "1%" isn't an empty bar.
        var filled = Int((clamped / 100 * Double(cells)).rounded())
        if clamped > 0 && filled == 0 { filled = 1 }
        if clamped >= 100 { filled = cells }
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: cells - filled)
    }

    /// "in 1h 42m" / "in 4d 3h" / "any moment now" once the window has rolled over.
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        if seconds <= 0 { return "any moment now" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        if minutes > 0 { return "in \(minutes)m" }
        return "in under a minute"
    }

    /// Wall-clock expiry. Same-day windows show a time, later ones show a date.
    public static func expiry(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                              locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        var cal = calendar
        cal.timeZone = timeZone
        if cal.isDate(date, inSameDayAs: now) {
            f.setLocalizedDateFormatFromTemplate("jmm")           // 2:14 PM
        } else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                                to: cal.startOfDay(for: date)).day, days < 7 {
            f.setLocalizedDateFormatFromTemplate("EEE jmm")       // Thu 2:14 PM
        } else {
            f.setLocalizedDateFormatFromTemplate("EEE d MMM jmm") // Thu 14 Aug 2:14 PM
        }
        return f.string(from: date)
    }

    /// "resets 2:14 PM · in 1h 42m", or a plain note when the provider gave no reset time.
    public static func resetPhrase(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "reset time not reported" }
        return "resets \(expiry(date, now: now)) · \(countdown(to: date, now: now))"
    }

    /// "12s ago" / "3m ago" / "never".
    public static func relativeAge(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = Int(max(0, now.timeIntervalSince(date)).rounded())
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
