# PuppyBar — project rules

Read [SPEC.md](../SPEC.md) first. It is the single source of truth.

## Build & test

```bash
swift run PuppyBarTests   # 132 checks — must pass before any claim of "working"
./build.sh                # test + build into ./dist
./build.sh install        # test + build + copy to /Applications + relaunch
```

There is no Xcode on this machine, only Command Line Tools. **Do not add an XCTest target**
or anything requiring `xcodebuild` — it will not build. See Decision D4 in SPEC.md.

## Verifying behaviour, not code

`--dump` prints the exact menu contents to the terminal:

```bash
/Applications/PuppyBar.app/Contents/MacOS/PuppyBar --dump
```

Use it instead of guessing. It renders from the same `MenuText` source as the real menu,
so if it is right, the menu is right. `--paw <path> [size]` writes the icon to a PNG.

## Invariants

- **One source of truth for rendered text.** Every percentage, bar, countdown and date
  string comes from `PuppyBarCore/Format.swift`; every menu line from `MenuText.swift`.
  Never format a value inline in `AppDelegate`.
- **Never return 0 for unparseable usage.** A missing or garbage value must be `nil` and
  surface as a visible message. A silent 0 renders as a reassuring "100% left" — the worst
  possible failure for this app.
- **Errors are always shown.** Every failure path puts a human-readable reason in the menu.
  No empty rows, no swallowed exceptions.
- **Secrets live in the Keychain only.** Never write a token to a file, a log, or a
  `--dump` output. `Keychain.swift` is the only place that touches them.

## Scope

Claude: session (5h) + weekly (7d). ChatGPT: weekly. That is the whole product.
Do not add providers, charts, or history without asking — see the Decisions Log.
