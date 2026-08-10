import Foundation

/// Turning raw provider responses into `Window`s. Kept AppKit-free so it can be tested hard.
public enum Parsing {

    /// Anthropic's `anthropic-ratelimit-unified-*-utilization` header.
    ///
    /// The header has been observed in two shapes across Claude Code versions:
    /// an integer percentage ("38") and a 0.0–1.0 fraction ("0.38"). We accept both.
    /// Values from zero through one are fractions, including a bare "1": Anthropic uses
    /// that value to mean the window is fully used. A one-percent header is therefore
    /// inherently ambiguous, but showing 1% at a hard limit is the harmful failure.
    /// Returns nil for anything unparseable rather than guessing. (EDGE-03)
    public static func utilizationPercent(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces)
        // Anthropic documents plain decimal values. Reject scientific notation and other
        // shapes that Double accepts but whose intended scale is ambiguous.
        guard s.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(s), value.isFinite, value >= 0 else { return nil }
        if value <= 1.0 { return value * 100 }
        return value
    }

    /// Anthropic reset headers are epoch seconds; some builds send an ISO-8601 timestamp.
    public static func resetDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let epoch = Double(s), epoch.isFinite {
            // Sanity window: reject absurd epochs so a bad header can't render "resets in 1970".
            guard epoch > 1_000_000_000, epoch < 4_000_000_000 else { return nil }
            return Date(timeIntervalSince1970: epoch)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    /// Build Claude's two windows from a response's headers.
    /// Header lookup is case-insensitive because URLSession's casing is not guaranteed.
    public static func anthropicWindows(headers: [String: String]) -> [Window] {
        let fiveHours: TimeInterval = 5 * 60 * 60
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        var h: [String: String] = [:]
        var ambiguous: Set<String> = []
        for (key, value) in headers {
            let normalizedKey = key.lowercased()
            if let existing = h[normalizedKey], existing != value {
                // A Dictionary can hold keys differing only by case, but an HTTP header
                // cannot safely have two conflicting values. Never choose one at random.
                ambiguous.insert(normalizedKey)
            } else {
                h[normalizedKey] = value
            }
        }
        for key in ambiguous { h.removeValue(forKey: key) }
        var windows: [Window] = []
        if let used = utilizationPercent(h["anthropic-ratelimit-unified-5h-utilization"]) {
            windows.append(Window(label: "Session (5h)", usedPercent: used,
                                  resetsAt: resetDate(h["anthropic-ratelimit-unified-5h-reset"]),
                                  duration: fiveHours))
        }
        if let used = utilizationPercent(h["anthropic-ratelimit-unified-7d-utilization"]) {
            windows.append(Window(label: "Weekly (7d)", usedPercent: used,
                                  resetsAt: resetDate(h["anthropic-ratelimit-unified-7d-reset"]),
                                  duration: sevenDays))
        }
        // Opus has its own weekly cap on some plans; show it when present.
        if let used = utilizationPercent(h["anthropic-ratelimit-unified-7d-opus-utilization"]) {
            windows.append(Window(label: "Weekly Opus (7d)", usedPercent: used,
                                  resetsAt: resetDate(h["anthropic-ratelimit-unified-7d-opus-reset"]),
                                  duration: sevenDays))
        }
        return windows
    }

    /// `chatgpt.com/backend-api/wham/usage` payload.
    /// Only the weekly window is surfaced — ChatGPT quotas are weekly, per KP's spec.
    public struct OpenAIUsage: Equatable {
        public let planLabel: String?
        public let windows: [Window]
        public let rateLimited: Bool
    }

    public static func openAIUsage(json: Any) -> OpenAIUsage? {
        guard let root = json as? [String: Any] else { return nil }
        let plan = (root["plan_type"] as? String).map { $0.capitalized }
        let rl = root["rate_limit"] as? [String: Any]
        let limitReached = (rl?["limit_reached"] as? Bool) ?? false

        var windows: [Window] = []
        func window(_ key: String, label: String) {
            guard let w = rl?[key] as? [String: Any] else { return }
            guard let used = numeric(w["used_percent"]) else { return }
            var reset: Date?
            if let at = numeric(w["reset_at"]), at > 1_000_000_000, at < 4_000_000_000 {
                reset = Date(timeIntervalSince1970: at)
            } else if let after = numeric(w["reset_after_seconds"]), after >= 0 {
                reset = Date().addingTimeInterval(after)
            }
            // Label the window by its real duration when the API tells us.
            var finalLabel = label
            let duration = numeric(w["limit_window_seconds"]).flatMap { $0 > 0 ? $0 : nil }
            if let duration {
                finalLabel = "\(label) (\(durationLabel(duration)))"
            }
            windows.append(Window(label: finalLabel, usedPercent: used, resetsAt: reset,
                                  duration: duration))
        }
        window("primary_window", label: "Weekly")
        window("secondary_window", label: "Secondary")

        guard !windows.isEmpty else { return nil }
        return OpenAIUsage(planLabel: plan, windows: windows, rateLimited: limitReached)
    }

    /// 604800 -> "7d", 18000 -> "5h", 3600 -> "1h".
    public static func durationLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s % 86400 == 0 { return "\(s / 86400)d" }
        if s % 3600 == 0 { return "\(s / 3600)h" }
        return "\(s / 60)m"
    }

    /// JSON numbers arrive as Int, Double, or String depending on the provider's mood.
    public static func numeric(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}
