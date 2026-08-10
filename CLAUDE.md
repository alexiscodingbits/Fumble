# CLAUDE.md — Fumble

Context for working on this project in a fresh session.

## What this is

**Fumble** is a native macOS menu-bar app (Swift/SwiftPM, macOS 14+) that passively watches how
you type all day, works out which keys and key-transitions actually cost you time, and (soon)
generates drills from them. The pitch: keybr without the cold start, and against the text you
really type rather than synthetic letter soup.

Owner: Alex. **Free and open source**, no revenue plan for v1 — it's a publicity/credibility play
and the data-gathering platform for v2.

Strategy, competitive research and the IP analysis live in the personal vault:
`~/vaults/personal/Business Ideas/Typing Coach/`. Read that before making product decisions —
particularly `Pulse teardown.md` (the competitor) and `Product plan — v1 and v2.md`.

## Status

**M1 complete.** 57 tests green, 0 build warnings, universal binary, ad-hoc signed, running.

- ✅ **M1** — CGEvent tap, provenance filtering, latency histograms, per-key/bigram/app stats,
  JSON-per-day persistence, weak-spot ranking, menu-bar dropdown.
- ⏳ **M2** — validate the injected-keystroke filter against real automation (Keyboard Maestro,
  Hammerspoon, `osascript`, text expanders, Copilot). **The schedule risk.** The mechanism is
  written and unit-tested against synthetic input, but never verified against real tools.
- ⏳ **M3** — keyboard heatmap, history/trends beyond today.
- ⏳ **M4** — drill generation from weak spots. This is where it stops being a tracker.
- ⏳ **M5** — Developer ID + notarization, Homebrew cask, Sparkle updater.
- ⏳ **v2** — word/token-level coaching, corpus derived **from disk** (repos + shell history),
  ranked with tap timing. Decided: the tap must never see words.

## Repo layout

```
FumbleCore/                        the SwiftPM package (all code)
  Package.swift                    2 libraries + 2 executables + 2 test targets, .macOS(.v14)
  Sources/
    FumbleCore/                    PURE model — Foundation ONLY (no AppKit/SwiftUI/CoreGraphics)
      LatencyHistogram.swift       28 fixed buckets; percentiles by interpolation
      KeyIdentity.swift            keycode → label/finger tables; BigramIdentity
      DayStats.swift               THE ON-DISK FORMAT. Counters + histograms, no sequence
      StatsRecorder.swift          the state machine: KeyEvent → DayStats
      WeakSpots.swift              baseline + ranking by time cost
      StatsStore.swift             one JSON file per day, atomic writes
    FumbleUI/                      PURE presentation logic — no SwiftUI import
      Formatters.swift, MenuViewState.swift
    FumbleApp/                     the ONLY target importing SwiftUI/AppKit/CoreGraphics
      EventTap.swift               CGEventTap (.listenOnly), provenance checks
      AppCoordinator.swift         wiring: tap + recorder + store + day rollover + flush
      FumbleApp.swift, DropdownView.swift
    fumble-cli/main.swift          inspection tool; `--json` dumps stored data verbatim
  Tests/FumbleCoreTests/, Tests/FumbleUITests/    Swift Testing (import Testing)
scripts/bundle-app.sh              universal build → assemble → sign → dist/Fumble.app
PRIVACY.md                         the privacy claims + how to verify them. Keep it accurate.
```

## Build / test / run

```sh
cd FumbleCore && swift build      # must be 0 warnings
cd FumbleCore && swift test       # 57 tests, must stay green
bash scripts/bundle-app.sh        # from repo root
ditto dist/Fumble.app /Applications/Fumble.app && open /Applications/Fumble.app
cd FumbleCore && swift run fumble-cli          # inspect today
```

## ⚠️ Critical gotchas

- **Input Monitoring resets on every rebuild.** macOS ties TCC permission to the code signature,
  and ad-hoc signatures get a new cdhash whenever the binary changes. Expect to re-grant after
  each build until there's a stable Developer ID. This is the single biggest dev friction.
- **It's Input Monitoring, NOT Accessibility.** `AXIsProcessTrusted()` reflects the wrong
  permission and gives false positives. Use `CGPreflightListenEventAccess()` /
  `CGRequestListenEventAccess()`. Getting this wrong produces an app that thinks it has
  permission and silently records nothing.
- **macOS shows the permission prompt only once per app identity.** After a denial the user must
  go to System Settings, so the UI must always offer that route (`openPrivacySettings`).
- **Never let a `CGEvent` cross into main-actor isolation.** It isn't `Sendable` and Swift 6 will
  reject it. `EventTap.extract` reads the fields in the nonisolated callback and forwards a
  `RawKeyEvent` of scalars. Keep that boundary.
- **Always re-enable a disabled tap.** macOS kills taps whose callback is slow
  (`tapDisabledByTimeout`) and on some wake transitions. Silently losing capture is the worst
  failure mode this app has — the stats would just quietly stop being true.
- **`breakSequence()` on every discontinuity** — app switch, sleep/wake, secure input, backspace,
  modifier, navigation key. Miss one and you fabricate a bigram the user never typed and record
  the intervening seconds as its latency.
- **The baseline is the median of per-key p95s, NOT the p95 of pooled keystrokes.** Pooling
  weights by frequency, so a frequent slow key drags the baseline toward itself and masks its own
  slowness — exactly the keys most worth fixing. This was caught by a test
  (`ranksByTimeCost`); don't "simplify" it back.
- **p95 with a ≤5% tail sits at the bucket boundary, not in the tail.** Documented in
  `p95AtExactBoundary`. p95 measures regular fumbles, not worst case. Don't treat it as a max.
- **`DayStats` is the file format.** `KeyIdentity.label` strings and `BigramIdentity.storageKey`
  are persisted; renaming one orphans historical data. Bump `schemaVersion` for incompatible
  changes — the loader ignores files from a future version rather than misreading them.
- **`wordsPerMinute` guards `activeSeconds > 0` separately** from the minimum threshold, or a
  caller passing 0 gets NaN into the formatter.
- **Rare-bigram pruning is a privacy control, not an optimisation.** `pruneRareBigrams` runs on
  the persistence snapshot only. Don't move it, and don't raise the threshold silently.

## Conventions

- **Pure-library boundary:** `FumbleCore` and `FumbleUI` import no UI frameworks. All UI in
  `FumbleApp`.
- **TDD for pure logic**; build-verified + visual check for SwiftUI views (can't be tested
  headlessly).
- Nil, not zero, for "we don't know yet". A fresh install reading `0 WPM` looks broken, and an
  empty weak-spots list reads as "you have no weaknesses" rather than "not enough data".
- **Every exclusion is counted and surfaced** in the dropdown. The WPM number must be auditable
  rather than magic — that's the differentiator against trackers that report 400 WPM on a paste.
- Commit messages end with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## Privacy invariants — do not regress these

These are load-bearing product claims, documented in `PRIVACY.md`:

1. Physical keycodes only. **Never** resolve keycode → character (that's reconstructing text).
2. No ordered sequence persisted. The recorder holds exactly one previous key in memory.
3. Secure input (`IsSecureEventInputEnabled()`) drops the event before any counter moves.
4. No network code anywhere in the app. Verified with `lsof -i -a -p "$(pgrep -x Fumble)"`.
5. Tap is `.listenOnly` — the OS enforces that we can't modify or inject events.
