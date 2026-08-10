# PuppyBar — SPEC

> Single living source of truth for this project. Always current. No parallel session log.

**Last updated:** 2026-08-10

---

## 1. What it is

A native macOS menu-bar app. A puppy paw sits in the menu bar. Click it to see:

- **Claude** — session (5-hour) window *and* weekly (7-day) window, each with % used
  and the exact date/time it expires. A small darker-neutral track on the reset line shows
  how much of the period has elapsed. Weekly Opus cap shown too when the account has one.
- **ChatGPT** — weekly window with % used, a right-aligned elapsed-period track, and expiry.

Session usage is Claude-only by design: OpenAI's consumer quotas are weekly, so there is
no 5-hour window to show.

## 2. Why it exists

KP runs both Claude and ChatGPT heavily and wants one glanceable answer to
"how much have I used, and when does it reset?" without opening two websites.

## 3. Architecture

```
Sources/
  PuppyBarCore/     Pure logic — no AppKit. Parsing, formatting, models, menu text.
    Models.swift      Window, ProviderState, ProviderSnapshot, Severity
    Parsing.swift     Anthropic headers + ChatGPT JSON -> Window
    Format.swift      Every percentage, bar, countdown and date string (ARCH-04)
    MenuText.swift    Every rendered line — menu and --dump share this
  PuppyBar/         The app.
    main.swift        Entry point + --dump / --paw flags
    AppDelegate.swift NSStatusItem, menu, polling, Launch at Login
    Providers.swift   AnthropicProvider, OpenAIProvider
    Keychain.swift    PuppyBar's own Keychain drawer
    ConnectWindow.swift  Where the Claude token is pasted
    PawIcon.swift     The paw, drawn in code
    Diagnostics.swift --dump and --paw implementations
  PuppyBarTests/    Test suite as a plain executable (see Decision D4)
```

**Data flow:** timer (5 min) *or* menu-open → both providers fetch in parallel →
`ProviderSnapshot` per provider → `MenuText` renders → menu + menu-bar title update.

## 4. Data sources

### Claude
`POST https://api.anthropic.com/v1/messages` — a 1-token Haiku ping. The usage numbers
come from the **response headers**, not the body:

| Header | Meaning |
|---|---|
| `anthropic-ratelimit-unified-5h-utilization` | session % used |
| `anthropic-ratelimit-unified-5h-reset` | session reset (epoch) |
| `anthropic-ratelimit-unified-7d-utilization` | weekly % used |
| `anthropic-ratelimit-unified-7d-reset` | weekly reset (epoch) |
| `anthropic-ratelimit-unified-7d-opus-utilization` | weekly Opus cap, when present |

Auth: a token from `claude setup-token`, pasted by the user into the Connect window,
stored in the macOS Keychain under service `PuppyBar` / account `anthropic-oauth-token`.

### ChatGPT
`GET https://chatgpt.com/backend-api/wham/usage` with the access token from
`~/.codex/auth.json` (or `$CODEX_HOME/auth.json`). The file is re-read on every poll so
background token refreshes by the ChatGPT/Codex app are picked up without a restart.
Returns `rate_limit.primary_window` with `used_percent`, `limit_window_seconds`, `reset_at`.

## 5. Decisions Log

| # | Decision | Rejected alternative | Why |
|---|---|---|---|
| D1 | Read Claude usage from rate-limit **headers** on a 1-token ping | `/api/oauth/usage` | That endpoint rate-limits so aggressively it can't be polled (anthropics/claude-code#31637). Headers come back on every response, **including 429s**, which is exactly when you most want the number. |
| D2 | Native Swift + AppKit | Python + rumps (AIQuotaBar's stack) | No Python venv to rot, no runtime deps, real `.app` for Login Items. Machine has Swift 6.1 via Command Line Tools — Xcode not required. |
| D3 | Claude token pasted by the user into a Keychain-backed window | Scraping browser cookies / Claude.app's Electron Safe Storage | Cookie scraping is fragile and invasive. Nothing on this machine exposes a reusable Claude API token — the Keychain entries hold only MCP plugin tokens. |
| D4 | Tests are a plain executable (`swift run PuppyBarTests`) | XCTest | XCTest ships with Xcode; this machine has Command Line Tools only. Requiring a 15 GB Xcode install to run tests is a worse trade than a 40-line harness. Exits non-zero on failure, so it still gates the build. |
| D5 | Paw drawn in code as a template image | Shipping a PNG asset | Crisp at any scale, and template mode auto-inverts for light/dark menu bars. |
| D6 | ChatGPT shows weekly only | Also showing a session window | OpenAI consumer plans are weekly-only; `secondary_window` came back `null` on this account. The parser handles it if it ever appears. |
| D7 | No desktop notifications in v1 | 80%/95% alerts like AIQuotaBar | `UNUserNotificationCenter` is unreliable for an unsigned, non-notarised local build. Better to ship nothing than a half-working alert. Revisit if the app gets signed. |
| D8 | Menu bar shows the paw only — no percentage | Worst-case % beside the paw | KP tracks three windows (Claude session, Claude weekly, ChatGPT weekly) and needs all three, so he clicks regardless. One number can't represent three and just adds noise. All three now live in the hover tooltip for a no-click peek. |
| D9 | Menu items are `isEnabled = true` with `menu.autoenablesItems = false` | Disabled non-interactive items | macOS dims disabled items regardless of the foreground colour set on the attributed title, which made the CLAUDE / CHATGPT headings look greyed out. A nil action keeps them inert while the text renders at full strength. Superseded in practice by D10 for provider content — kept here as the record of the first attempt. |
| D10 | Provider sections render as a custom `NSView` (`ProviderSectionView`) set as the `NSMenuItem`'s `.view`, laid out with explicit frames | `NSMenuItem.attributedTitle` with embedded `\n` for multi-line rows | AppKit's own height calculation for multi-line attributedTitle text is unreliable — this was the actual root cause of the dropdown resizing oddly on every open and leaving blank space below Quit, not a font/colour issue. A view we size ourselves has a frame we control exactly. Real drawn progress bars (`ProgressBarView`) replaced the unicode-block bars, removing monospace-font drift as a source of uneven rows. |
| D11 | `NSApp.mainMenu` is set to a minimal Edit menu (`paste:` / `copy:` / `cut:` / `selectAll:` with nil targets) at launch, even though it's never visibly shown | Leaving `mainMenu` unset | Menu-bar-only (`.accessory`) apps have no visible menu bar, so AppKit has nowhere to register ⌘V — it silently no-ops in the Connect Claude field. Assigning `mainMenu` still works for key-equivalent routing even though it's never rendered; this is the standard fix for text editing in `LSUIElement` apps. |
| D12 | Menu-open refresh is throttled to once per 20s (`staleAfter`); background 5-minute ticks skip the rebuild entirely while the menu is open | Rebuilding on every open + every background tick, as v1 did | v1 rebuilt the menu twice per open — once instantly, once ~1s later when the async fetch completed — which is what actually produced "keeps changing size" on every single click. Now: instant paint from cache on open, re-fetch only if stale, and background ticks never resize a menu the user is currently looking at. |
| D13 | Treat every Claude utilization value from `0` through `1` as a fraction, so bare `1` means fully used | Treat bare `1` as one percent | Anthropic's live header convention uses `1` / `1.0` for an exhausted quota. Showing 1% used at a hard limit is the more harmful interpretation. Scientific notation and conflicting case-duplicate headers are rejected rather than guessed. |
| D14 | A Claude HTTP 429 renders its session as `100% used` and no separate warning row | Show the raw header value plus “Limit reached” | A 429 is definitive that the current session is exhausted; a contradictory utilization header made the menu say “99% left” and “Limit reached” simultaneously. Only the session is overridden—the weekly figure remains the value Anthropic sent. |
| D15 | Provider sections use a calm typographic hierarchy and contextual reconnect actions; menu refreshes never rebuild while open | Coloured provider branding, global Connect option, and repainting after an open-menu refresh | Larger neutral provider names anchor the menu; small muted labels and a deeper green keep normal usage quiet. Purple/blue branding competed with severity colours. A reconnect action belongs next to the affected provider. Fresh data is staged until close so the menu cannot jump while being read. |
| D16 | Every quota is shown as `% used`; all footer actions use the same foreground strength | Mixing “% left” with “% used”, or dimming only Refresh and Quit | A single direction makes all three quotas comparable at a glance. Footer actions are equally interactive, so differing text weights suggested a false disabled state. |
| D17 | Hide plan labels and animate every actionable custom row on hover | Showing a possibly stale plan name or leaving custom controls without hover feedback | The plan label misrepresented the current subscription. Custom views bypass AppKit’s standard item highlight, so each action row draws a restrained accent-tint fade on mouse enter/exit. |
| D18 | Put refresh in a fixed PuppyBar header with its age and a reload icon; use playful provider-specific heading tints | A loose Refresh row in the footer and black provider headings | The header makes refresh discoverable without competing with settings. It invokes the existing parallel provider poll, and its refresh age tells KP when the shown values were fetched. Claude's purple and ChatGPT's teal provide lighthearted identity without changing the meaning of quota-severity colours. |
| D19 | Show a darker-neutral elapsed-period track at the right of the reset line when the provider supplies both reset time and period length | Add a “Time X% elapsed” line, or guess a progress bar from the reset countdown alone | The track answers how much of the 5-hour or 7-day window has passed without adding vertical clutter or confusing it with quota used. It is absent rather than invented when either input is missing or invalid. |

## 6. Current State

**Working and verified 2026-08-10:**
- ChatGPT weekly usage — live, real data, no setup required. Verified end-to-end via `--dump`.
- Paw icon renders correctly at 18px (menu bar) and 256px.
- 132 automated checks pass, including a harness self-test that proves failures are detected.
- `.app` builds and installs without Xcode.
- Claude values `0` through `1`, including a bare `1`, now render as fractions; a full
  session displays as 100% used. The menu is narrower and denser, with neutral provider
  headings and no redundant separator before Quit.
- A Claude HTTP 429 now renders the session as `100% used` and removes the redundant
  “Limit reached” row, while leaving the independently tracked weekly usage unchanged.
- Claude and ChatGPT are now clear section headings; quota rows are visually subordinate,
  calm usage uses a darker green, and reconnect actions appear only inside a disconnected
  provider section. Launch at Login uses a right-aligned tick. Menu refreshes stage their
  redraw until after the menu closes, so its size cannot change mid-glance.
- Every provider now consistently shows percentage used; Refresh, Launch at Login, and
  Quit PuppyBar use equal-strength footer text.
- ChatGPT's plan label is intentionally hidden. Every custom Refresh, Launch at Login,
  Quit, and reconnect row now gives clear animated hover feedback.
- The top strip is now PuppyBar, its refresh age, and a reload icon that starts a fresh
  parallel poll. Claude and ChatGPT headings use purple and teal respectively.
- Each quota has a compact, darker-neutral elapsed-period bar on the right of its reset
  line when both the reset time and period length are available.

**Waiting on user action:**
- Claude side shows "Not connected" until KP runs `claude setup-token` and pastes the
  token into the Connect window.

## 7. Known Issues

| # | Issue | Severity |
|---|---|---|
| K1 | **Claude header parsing is unverified against a live response.** The header *names* come from rjwalters/claude-monitor, and the parser accepts both integer-percent and 0.0–1.0 formats, but no real Anthropic response has been observed yet on this machine. First connection is the real test. | Medium — flag, don't assume |
| K2 | Ad-hoc code signature changes on every rebuild, so macOS may re-prompt for Keychain access after `./build.sh install`. Harmless; click Allow. | Low |
| K3 | Unsigned/non-notarised. First launch from `/Applications` may need right-click → Open. | Low |
| K4 | Each Claude poll costs ~1 Haiku output token. At a 5-minute interval that's ~288 tokens/day. Negligible, but it is not literally free. | Low |
| K5 | The rendered menu has still not been inspected as pixels. First attempt: no screen-capture access. Second attempt: `computer-use` request_access couldn't resolve "PuppyBar" (background-only, no Dock icon, not in its known-apps list), so it remains unverified by me. Root causes for greying and resizing were identified and fixed directly (D9–D12), and `--dump` confirms the data layer, but the actual on-screen look and the ⌘V fix specifically need KP's eyes. | Medium — genuinely unverified, not just unproven |

## 8. Testing

`swift run PuppyBarTests` — 132 checks. Covers: header format ambiguity (integer vs
fraction), garbage headers returning nil rather than a reassuring 0, absurd epochs,
missing reset times, null `secondary_window`, string-encoded numbers, over-100% usage,
negative usage, past reset times, clock skew, bar width invariance, a bare full-fraction
Claude value, near-full display rounding, conflicting duplicate header casing, exhausted
session display, elapsed-period bounds and invalid inputs, the open-menu no-rebuild rule,
and human-readable refresh status.

The suite begins with a **deliberate failing check** and aborts with exit code 2 if the
harness doesn't catch it — no green that lies. (TEST-12)

## 9. Handoff

Everything is in `/Users/kanwar/Code/PuppyBar`. `./build.sh` builds; `./build.sh install`
builds, copies to `/Applications`, and relaunches. `--dump` prints the menu to the
terminal, which is the fastest way to debug without hunting for the paw.

**Next session should start by confirming K1** — whether the Claude numbers came through
correctly once the token is connected. The parser now treats bare `1` as fully used; the
remaining open question is only first-party live-header capture on this Mac.

## 10. Deployment

Local Mac only. Not a pm2/Tailscale service. "Launch at Login" is a menu toggle
(`SMAppService`), which requires the app to live in `/Applications`.

## 11. Provenance

Not affiliated with Anthropic or OpenAI. Uses undocumented internal endpoints that may
change without notice. Approach and endpoint knowledge adapted from the MIT-licensed
[rjwalters/claude-monitor](https://github.com/rjwalters/claude-monitor) (Anthropic
rate-limit headers, ChatGPT `wham/usage`) and
[yagcioglutoprak/AIQuotaBar](https://github.com/yagcioglutoprak/AIQuotaBar)
(80/95% severity convention, menu layout). Code here is original.
