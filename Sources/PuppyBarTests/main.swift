import Foundation
import PuppyBarCore

// ---------------------------------------------------------------------------
// TEST-12: prove the harness can fail before trusting any green it reports.
// A test runner that always passes is worse than no runner at all.
// ---------------------------------------------------------------------------
T.group("harness-self-test") {
    T.check(false, "deliberate failure — the harness must notice this")
    guard T.failures.count == 1 else {
        print("❌ FATAL: harness did not record a deliberate failure. Green would be a lie.")
        exit(2)
    }
    // Injected failure detected; clear it and run the real suite.
    T.failures.removeAll()
    T.checks = 0
    print("✓ harness self-test: a failing check is detected and reported")
}

// ---------------------------------------------------------------------------
// Anthropic utilisation headers
// ---------------------------------------------------------------------------
T.group("anthropic-utilization") {
    T.eq(Parsing.utilizationPercent("38"), 38, "integer percent header")
    T.eq(Parsing.utilizationPercent("0"), 0, "zero")
    T.eq(Parsing.utilizationPercent("100"), 100, "full")
    T.near(Parsing.utilizationPercent("0.38"), 38, 0.001, "fraction is scaled to percent")
    T.near(Parsing.utilizationPercent("1.0"), 100, 0.001, "1.0 as a decimal means 100%")
    T.eq(Parsing.utilizationPercent("1"), 100, "bare 1 means a fully used Claude window")
    T.eq(Parsing.utilizationPercent("0.01"), 1, "small fraction becomes one percent")
    T.eq(Parsing.utilizationPercent("1.000"), 100, "full fraction with trailing zeroes")
    T.isNil(Parsing.utilizationPercent("1e-1"), "scientific notation has ambiguous scale")
    T.near(Parsing.utilizationPercent("38.5"), 38.5, 0.001, "decimal above 1.0 is already a percent")
    T.eq(Parsing.utilizationPercent("140"), 140, "over-limit utilisation survives")
    T.eq(Parsing.utilizationPercent("  42 "), 42, "whitespace tolerated")

    // Returning 0 for garbage would render a reassuring, wrong "0% used". (EDGE-03)
    for bad in ["", "   ", "n/a", "38%", "-5", "inf", "NaN", "1e999"] {
        T.isNil(Parsing.utilizationPercent(bad), "garbage \"\(bad)\" must be nil, never 0")
    }
    T.isNil(Parsing.utilizationPercent(nil), "missing header is nil")
}

// ---------------------------------------------------------------------------
// Reset timestamps
// ---------------------------------------------------------------------------
T.group("reset-dates") {
    T.eq(Parsing.resetDate("1786883229")?.timeIntervalSince1970, 1786883229, "epoch seconds")
    for bad in ["0", "1", "99999999999", "-1786883229", "", "soon"] {
        T.isNil(Parsing.resetDate(bad), "absurd epoch \"\(bad)\" rejected — no \"resets in 1970\"")
    }
    T.isNil(Parsing.resetDate(nil), "missing reset header is nil")
    T.notNil(Parsing.resetDate("2026-08-09T18:00:00Z"), "ISO-8601")
    T.notNil(Parsing.resetDate("2026-08-09T18:00:00.123Z"), "ISO-8601 with fractional seconds")
}

// ---------------------------------------------------------------------------
// Claude windows
// ---------------------------------------------------------------------------
T.group("anthropic-windows") {
    let windows = Parsing.anthropicWindows(headers: [
        "Anthropic-RateLimit-Unified-5h-Utilization": "38",
        "anthropic-ratelimit-unified-5h-reset": "1786883229",
        "ANTHROPIC-RATELIMIT-UNIFIED-7D-UTILIZATION": "21",
        "anthropic-ratelimit-unified-7d-reset": "1787883229",
    ])
    T.eq(windows.count, 2, "both windows parsed")
    T.eq(windows.first?.label, "Session (5h)", "session labelled")
    T.eq(windows.first?.usedPercent, 38, "session usage")
    T.eq(windows.first?.remainingPercent, 62, "session remaining")
    T.eq(windows.first?.duration, 18_000, "session has a five-hour period")
    T.eq(windows.last?.label, "Weekly (7d)", "weekly labelled")
    T.eq(windows.last?.duration, 604_800, "weekly has a seven-day period")
    T.notNil(windows.first?.resetsAt, "session reset parsed")

    let partial = Parsing.anthropicWindows(headers: ["anthropic-ratelimit-unified-5h-utilization": "10"])
    T.eq(partial.count, 1, "window survives a missing reset header")
    T.isNil(partial.first?.resetsAt, "missing reset is nil, window still shown")

    T.eq(Parsing.anthropicWindows(headers: [:]).count, 0, "no headers -> no windows")
    T.eq(Parsing.anthropicWindows(headers: ["content-type": "application/json"]).count, 0,
         "irrelevant headers -> no windows")
    T.eq(Parsing.anthropicWindows(headers: ["anthropic-ratelimit-unified-7d-opus-utilization": "12"])
        .map(\.label), ["Weekly Opus (7d)"], "Opus weekly cap shown when present")

    let nearlyFull = Parsing.anthropicWindows(headers: [
        "anthropic-ratelimit-unified-5h-utilization": "0.995",
    ])
    T.near(nearlyFull.first?.usedPercent, 99.5, 0.001, "0.995 means 99.5% used")
    T.eq(Format.percent(nearlyFull.first?.usedPercent ?? -1), "100%", "display rounds 99.5% to 100%")

    T.eq(Parsing.anthropicWindows(headers: [
        "Anthropic-RateLimit-Unified-5h-Utilization": "0.38",
        "anthropic-ratelimit-unified-5h-utilization": "1.0",
    ]).count, 0, "conflicting case-duplicate headers are not chosen at random")
}

// ---------------------------------------------------------------------------
// ChatGPT payload — modelled on the real response captured 2026-08-09
// ---------------------------------------------------------------------------
func chatGPTPayload(_ rateLimit: [String: Any]? = nil) -> [String: Any] {
    [
        "plan_type": "plus",
        "rate_limit": rateLimit ?? [
            "allowed": true,
            "limit_reached": false,
            "primary_window": [
                "used_percent": 5,
                "limit_window_seconds": 604800,
                "reset_after_seconds": 603821,
                "reset_at": 1786883229,
            ],
            "secondary_window": NSNull(),
        ],
    ]
}

T.group("chatgpt-usage") {
    let usage = Parsing.openAIUsage(json: chatGPTPayload())
    T.eq(usage?.planLabel, "Plus", "plan label")
    T.eq(usage?.windows.count, 1, "null secondary_window must not create a phantom row")
    T.eq(usage?.windows.first?.label, "Weekly (7d)", "weekly window labelled by real duration")
    T.eq(usage?.windows.first?.usedPercent, 5, "usage percent")
    T.eq(usage?.windows.first?.remainingPercent, 95, "remaining percent")
    T.eq(usage?.windows.first?.duration, 604_800, "reported weekly period retained")
    T.eq(usage?.windows.first?.resetsAt?.timeIntervalSince1970, 1786883229, "reset_at preferred")
    T.eq(usage?.rateLimited, false, "not rate limited")

    let hit = Parsing.openAIUsage(json: chatGPTPayload([
        "limit_reached": true,
        "primary_window": ["used_percent": 100, "limit_window_seconds": 604800],
    ]))
    T.eq(hit?.rateLimited, true, "limit_reached surfaces")
    T.eq(hit?.windows.first?.remainingPercent, 0, "nothing left")

    let fallback = Parsing.openAIUsage(json: chatGPTPayload([
        "primary_window": ["used_percent": 5, "reset_after_seconds": 3600],
    ]))
    T.near(fallback?.windows.first?.resetsAt?.timeIntervalSinceNow, 3600, 5,
           "falls back to reset_after_seconds when reset_at is absent")

    let strings = Parsing.openAIUsage(json: chatGPTPayload([
        "primary_window": ["used_percent": "7", "limit_window_seconds": "604800"],
    ]))
    T.eq(strings?.windows.first?.usedPercent, 7, "string-encoded numbers accepted")

    T.isNil(Parsing.openAIUsage(json: [] as [Any]), "array payload rejected")
    T.isNil(Parsing.openAIUsage(json: [:] as [String: Any]), "empty payload rejected")
    T.isNil(Parsing.openAIUsage(json: ["rate_limit": [:] as [String: Any]]), "empty rate_limit rejected")
    T.isNil(Parsing.openAIUsage(json: ["rate_limit": ["primary_window": ["reset_at": 1786883229]]]),
            "a window with no used_percent is not a window")

    T.eq(Parsing.durationLabel(604800), "7d", "7 day window")
    T.eq(Parsing.durationLabel(18000), "5h", "5 hour window")
    T.eq(Parsing.durationLabel(3600), "1h", "1 hour window")
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------
T.group("format") {
    T.eq(Format.percent(0), "0%", "zero percent")
    T.eq(Format.percent(38.4), "38%", "rounds down")
    T.eq(Format.percent(38.6), "39%", "rounds up")
    T.eq(Format.percent(140), "140%", "over 100 survives")
    T.eq(Format.usageLabel(usedPercent: 38), "38% used", "normal usage shows used quota")
    T.eq(Format.usageLabel(usedPercent: 100), "100% used", "exhausted usage is direct")

    T.eq(Format.bar(usedPercent: 0), "░░░░░░░░░░", "empty bar")
    T.eq(Format.bar(usedPercent: 100), "▓▓▓▓▓▓▓▓▓▓", "full bar")
    T.eq(Format.bar(usedPercent: 50), "▓▓▓▓▓░░░░░", "half bar")
    T.eq(Format.bar(usedPercent: 0.4), "▓░░░░░░░░░", "tiny usage still shows one cell")
    T.eq(Format.bar(usedPercent: 140), "▓▓▓▓▓▓▓▓▓▓", "over-limit clamps full")
    T.eq(Format.bar(usedPercent: -20), "░░░░░░░░░░", "negative clamps empty")
    T.eq(Format.bar(usedPercent: 50, cells: 0), "", "zero-width bar doesn't crash")
    var widthOK = true
    for p in stride(from: -10.0, through: 130.0, by: 3.7) where Format.bar(usedPercent: p).count != 10 {
        widthOK = false
    }
    T.check(widthOK, "bar is always exactly 10 cells wide, so menu rows stay aligned")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    T.eq(Format.countdown(to: now.addingTimeInterval(6120), now: now), "in 1h 42m", "hours and minutes")
    T.eq(Format.countdown(to: now.addingTimeInterval(356_400), now: now), "in 4d 3h", "days and hours")
    T.eq(Format.countdown(to: now.addingTimeInterval(300), now: now), "in 5m", "minutes only")
    T.eq(Format.countdown(to: now.addingTimeInterval(30), now: now), "in under a minute", "sub-minute")
    T.eq(Format.countdown(to: now.addingTimeInterval(-500), now: now), "any moment now",
         "a past reset never renders as negative time")
    T.eq(Format.countdown(to: now, now: now), "any moment now", "exactly now")

    T.eq(Format.resetPhrase(nil), "reset time not reported", "missing reset is stated, not hidden")

    T.eq(Format.relativeAge(nil, now: now), "never", "never fetched")
    T.eq(Format.relativeAge(now.addingTimeInterval(-12), now: now), "12s ago", "seconds")
    T.eq(Format.relativeAge(now.addingTimeInterval(-180), now: now), "3m ago", "minutes")
    T.eq(Format.relativeAge(now.addingTimeInterval(-7200), now: now), "2h ago", "hours")
    T.eq(Format.relativeAge(now.addingTimeInterval(4), now: now), "0s ago", "clock skew never shows negative age")
    T.eq(Format.refreshedStatus(nil, now: now), "Not refreshed yet", "empty refresh state is explicit")
    T.eq(Format.refreshedStatus(now.addingTimeInterval(-12), now: now), "Refreshed 12s ago",
         "header refresh age is human-readable")

    let fiveHours: TimeInterval = 18_000
    T.eq(Format.elapsedPeriodPercent(resetsAt: now.addingTimeInterval(fiveHours), duration: fiveHours, now: now),
         0, "a newly opened period is zero percent elapsed")
    T.eq(Format.elapsedPeriodPercent(resetsAt: now, duration: fiveHours, now: now),
         100, "an exactly expired period is fully elapsed")
    T.near(Format.elapsedPeriodPercent(resetsAt: now.addingTimeInterval(300), duration: fiveHours, now: now),
           100 - (300 / fiveHours * 100), 0.0001, "normal elapsed period is precise")
    T.eq(Format.elapsedPeriodPercent(resetsAt: now.addingTimeInterval(fiveHours + 1), duration: fiveHours, now: now),
         0, "provider clock ahead clamps to an empty time track")
    T.eq(Format.elapsedPeriodPercent(resetsAt: now.addingTimeInterval(-1), duration: fiveHours, now: now),
         100, "a past reset clamps to a full time track")
    T.isNil(Format.elapsedPeriodPercent(resetsAt: nil, duration: fiveHours, now: now),
            "no reset means no misleading time track")
    for badDuration in [TimeInterval?.none, 0, -1, .nan, .infinity] {
        T.isNil(Format.elapsedPeriodPercent(resetsAt: now, duration: badDuration, now: now),
                "invalid period length has no time track")
    }
    T.check(Format.bar(usedPercent: 80).hasPrefix("▓▓▓▓▓▓▓▓"), "time track uses elapsed percent")
}

// ---------------------------------------------------------------------------
// Severity + snapshot roll-up
// ---------------------------------------------------------------------------
T.group("severity") {
    T.eq(Severity.forUsed(0), .calm, "idle is calm")
    T.eq(Severity.forUsed(79.9), .calm, "just below warning")
    T.eq(Severity.forUsed(80), .warning, "warning boundary is inclusive")
    T.eq(Severity.forUsed(94.9), .warning, "just below critical")
    T.eq(Severity.forUsed(95), .critical, "critical boundary is inclusive")
    T.eq(Severity.forUsed(140), .critical, "over limit is critical")

    let snapshot = ProviderSnapshot(name: "Claude", state: .ok(planLabel: nil, windows: [
        Window(label: "Session (5h)", usedPercent: 38, resetsAt: nil),
        Window(label: "Weekly (7d)", usedPercent: 71, resetsAt: nil),
    ], rateLimited: false), fetchedAt: Date())
    T.eq(snapshot.worstUsedPercent, 71, "menu bar shows the most urgent window")

    let limitedClaude = ProviderSnapshot(name: "Claude", state: .ok(planLabel: nil, windows: [
        Window(label: "Session (5h)", usedPercent: 1, resetsAt: nil),
        Window(label: "Weekly (7d)", usedPercent: 40, resetsAt: nil),
    ], rateLimited: true), fetchedAt: Date())
    T.eq(limitedClaude.displayedWindows?.first?.usedPercent, 100,
         "a Claude 429 overrides a contradictory session header")
    T.eq(limitedClaude.displayedWindows?.last?.usedPercent, 40,
         "a Claude 429 preserves the separate weekly window")
    let limitedSection = MenuText.section(for: limitedClaude)
    T.eq(limitedSection.rows.count, 2, "limit state does not add a redundant warning row")
    T.check(limitedSection.rows.first?.primary.contains("100% used") == true,
            "limit state renders the session as 100% used")

    let datedWindow = Window(label: "Session (5h)", usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_700_000_000),
                             duration: 18_000)
    let datedRow = MenuText.row(for: datedWindow, now: Date(timeIntervalSince1970: 1_700_000_000))
    T.check(datedRow.primary.contains("7% used"), "time progress never changes quota usage")
    T.check(datedRow.secondary?.contains("resets") == true && !datedRow.primary.contains("Time"),
            "time track adds no redundant text line to the menu diagnostic")

    T.check(!MenuUpdatePolicy.shouldRebuildAfterRefresh(menuIsOpen: true),
            "a refresh never resizes an open menu")
    T.check(MenuUpdatePolicy.shouldRebuildAfterRefresh(menuIsOpen: false),
            "fresh data is painted once the menu closes")

    T.isNil(ProviderSnapshot(name: "Claude", state: .notConnected("x"), fetchedAt: nil).worstUsedPercent,
            "disconnected provider contributes no number")
    T.isNil(ProviderSnapshot(name: "Claude", state: .failed("x"), fetchedAt: nil).worstUsedPercent,
            "failed provider contributes no number")
    T.isNil(ProviderSnapshot(name: "Claude", state: .ok(planLabel: nil, windows: [], rateLimited: false),
                             fetchedAt: nil).worstUsedPercent,
            "ok-but-empty contributes no number")
}

// ---------------------------------------------------------------------------
// Menu bar tooltip — the no-click peek at all three windows
// ---------------------------------------------------------------------------
T.group("tooltip") {
    let claude = ProviderSnapshot(name: "Claude", state: .ok(planLabel: nil, windows: [
        Window(label: "Session (5h)", usedPercent: 38, resetsAt: nil),
        Window(label: "Weekly (7d)", usedPercent: 21, resetsAt: nil),
    ], rateLimited: false), fetchedAt: Date())
    let chatgpt = ProviderSnapshot(name: "ChatGPT", state: .ok(planLabel: "Plus", windows: [
        Window(label: "Weekly (7d)", usedPercent: 7, resetsAt: nil),
    ], rateLimited: false), fetchedAt: Date())

    let tip = MenuText.tooltip([claude, chatgpt])
    T.eq(tip.split(separator: "\n").count, 3, "all three windows appear in the tooltip")
    T.check(tip.contains("Claude Session (5h): 38% used"), "claude session line")
    T.check(tip.contains("Claude Weekly (7d): 21% used"), "claude weekly line")
    T.check(tip.contains("ChatGPT Weekly (7d): 7% used"), "chatgpt weekly line")
    T.eq(MenuText.section(for: chatgpt).header, "CHATGPT", "plan label is not rendered in the menu")

    let disconnected = ProviderSnapshot(name: "Claude", state: .notConnected("x"), fetchedAt: nil)
    T.check(MenuText.tooltip([disconnected]).contains("not connected"),
            "disconnected provider says so rather than vanishing")
    T.check(MenuText.tooltip([ProviderSnapshot(name: "Claude", state: .failed("x"), fetchedAt: nil)])
        .contains("couldn't check"), "failed provider says so")
    T.eq(MenuText.tooltip([]), "PuppyBar", "empty tooltip falls back to the app name")
}

T.report()
