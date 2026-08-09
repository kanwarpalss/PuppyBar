import Foundation

/// One rolling quota window (Claude session, Claude weekly, ChatGPT weekly).
public struct Window: Equatable {
    /// Human label, e.g. "Session (5h)".
    public let label: String
    /// Percent of the quota consumed, 0...100+ (can exceed 100 if the API says so).
    public let usedPercent: Double
    /// When this window rolls over. `nil` when the provider didn't tell us.
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// What one provider (Claude / OpenAI) reports after a poll.
public enum ProviderState: Equatable {
    /// Never polled yet.
    case idle
    /// No credentials found — actionable message for the user.
    case notConnected(String)
    /// Poll failed — the reason is always shown, never swallowed. (DEBUG-01)
    case failed(String)
    /// Good data. `planLabel` e.g. "Max" / "Plus". `rateLimited` = provider says you're cut off right now.
    case ok(planLabel: String?, windows: [Window], rateLimited: Bool)
}

public struct ProviderSnapshot: Equatable {
    public let name: String
    public let state: ProviderState
    public let fetchedAt: Date?

    public init(name: String, state: ProviderState, fetchedAt: Date?) {
        self.name = name
        self.state = state
        self.fetchedAt = fetchedAt
    }

    /// Highest utilisation across this provider's windows, for the menu bar summary.
    public var worstUsedPercent: Double? {
        guard case let .ok(_, windows, _) = state, !windows.isEmpty else { return nil }
        return windows.map(\.usedPercent).max()
    }
}

/// Colour band for a usage percentage. Thresholds mirror AIQuotaBar's 80/95 convention.
public enum Severity: Equatable {
    case calm      // < 80%
    case warning   // 80–94%
    case critical  // >= 95%

    public static func forUsed(_ percent: Double) -> Severity {
        if percent >= 95 { return .critical }
        if percent >= 80 { return .warning }
        return .calm
    }

    public var dot: String {
        switch self {
        case .calm: return "🟢"
        case .warning: return "🟡"
        case .critical: return "🔴"
        }
    }
}
