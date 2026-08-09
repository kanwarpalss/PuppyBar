# PuppyBar — SPEC

> Single living source of truth for this project. Always current. No parallel session log.

**Last updated:** 2026-08-09

---

## 1. What it is

A native macOS menu-bar app. A puppy paw sits in the menu bar next to your highest
current usage number. Click the paw to see:

- **Claude** — session (5-hour) window *and* weekly (7-day) window, each with % left
  and the exact date/time it expires. Weekly Opus cap shown too when the account has one.
- **ChatGPT** — weekly window with % left and expiry.

Session usage is Claude-only by design: OpenAI's consumer quotas are weekly, so there is
no 5-hour window to show.

## 2. Why it exists

KP runs both Claude and ChatGPT heavily and wants one glanceable answer to
"how much have I got left, and when does it reset?" without opening two websites.

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

## 6. Current State

**Working and verified 2026-08-09:**
- ChatGPT weekly usage — live, real data, no setup required. Verified end-to-end via `--dump`.
- Paw icon renders correctly at 18px (menu bar) and 256px.
- 91 automated checks pass, including a harness self-test that proves failures are detected.
- `.app` builds and installs without Xcode.

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

`swift run PuppyBarTests` — 91 checks. Covers: header format ambiguity (integer vs
fraction), garbage headers returning nil rather than a reassuring 0, absurd epochs,
missing reset times, null `secondary_window`, string-encoded numbers, over-100% usage,
negative usage, past reset times, clock skew, bar width invariance.

The suite begins with a **deliberate failing check** and aborts with exit code 2 if the
harness doesn't catch it — no green that lies. (TEST-12)

## 9. Handoff

Everything is in `/Users/kanwar/Code/PuppyBar`. `./build.sh` builds; `./build.sh install`
builds, copies to `/Applications`, and relaunches. `--dump` prints the menu to the
terminal, which is the fastest way to debug without hunting for the paw.

**Next session should start by confirming K1** — whether the Claude numbers came through
correctly once the token is connected.

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
