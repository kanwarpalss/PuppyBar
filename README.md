# PuppyBar 🐾

A puppy paw in your macOS menu bar that tells you how much Claude and ChatGPT you have left.

```
🐾 38%
─────────────────────────────────────────────
CLAUDE
🟢  Session (5h)     ▓▓▓▓░░░░░░  62% left
        resets 2:14 PM · in 1h 42m
🟡  Weekly (7d)      ▓▓▓▓▓▓▓▓░░  21% left
        resets Thu 14 Aug 9:00 AM · in 4d 3h
─────────────────────────────────────────────
CHATGPT · Plus
🟢  Weekly (7d)      ▓░░░░░░░░░  94% left
        resets Sun 16 Aug 5:57 PM · in 6d 23h
─────────────────────────────────────────────
Updated 4s ago
Refresh Now                              ⌘R
Connect Claude…
Launch at Login                           ✓
Quit PuppyBar                            ⌘Q
```

The number beside the paw is your **most urgent** window across both services.

## Install

```bash
./build.sh install
```

That runs the tests, builds `PuppyBar.app`, copies it to `/Applications`, and launches it.
No Xcode needed — Command Line Tools is enough.

If macOS blocks the first launch, right-click `PuppyBar.app` → **Open** (it's an unsigned
local build).

## Connecting

**ChatGPT works immediately** if you're signed in to the ChatGPT or Codex app — PuppyBar
reads the credentials already at `~/.codex/auth.json`.

**Claude needs one step:**

```bash
claude setup-token
```

Copy the token it prints, click the paw → **Connect Claude…**, paste, Save.

The token goes straight into your macOS Keychain (service `PuppyBar`). It is never written
to a file, never logged, and is sent only to `api.anthropic.com`.

## Everyday use

| Want | Do |
|---|---|
| Fresh numbers | Just click the paw — it refreshes on open |
| See it in the terminal | `/Applications/PuppyBar.app/Contents/MacOS/PuppyBar --dump` |
| Start automatically | Click the paw → Launch at Login |
| Remove the Claude token | Click the paw → Reconnect Claude… → Remove Token |

Colours: 🟢 under 80% used · 🟡 80–94% · 🔴 95%+.

## How it gets the numbers

- **Claude** — sends a 1-token ping to `api.anthropic.com/v1/messages` and reads the
  `anthropic-ratelimit-unified-*` response headers. These come back even when you're
  rate-limited, which is exactly when the number matters most.
- **ChatGPT** — reads `chatgpt.com/backend-api/wham/usage` with your existing session.

Polls every 5 minutes in the background, plus every time you open the menu.

## Development

```bash
swift run PuppyBarTests   # 91 checks
./build.sh                # build only, into ./dist
```

See [SPEC.md](SPEC.md) for architecture, the decisions log, and known issues.

## Honest caveats

- **Not affiliated with Anthropic or OpenAI.** These are undocumented internal endpoints.
  They can change or disappear without notice, and PuppyBar will show an error when they do
  rather than pretend everything is fine.
- Each Claude poll costs about one Haiku token (~288/day). Negligible, but not zero.
- The Claude header format hasn't been verified against a live response yet — see
  Known Issues in SPEC.md.

MIT. Endpoint approach adapted from [rjwalters/claude-monitor](https://github.com/rjwalters/claude-monitor)
and [AIQuotaBar](https://github.com/yagcioglutoprak/AIQuotaBar), both MIT.
