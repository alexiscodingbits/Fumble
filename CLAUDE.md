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

**Feature-complete, pre-release.** 185 tests green, 0 build warnings, universal binary,
Developer ID signed (notarization verified end-to-end once; release workflow automates it).

- ✅ **M1** — CGEvent tap, provenance filtering, latency histograms (adaptive per-transition
  motor filter), per-key/bigram/app stats, JSON-per-day persistence, weak-spot ranking.
- ✅ **M3** — dropdown dashboard (live WPM, Swift Charts trend, needs-work chips), Stats pane
  (relative-speed heatmap, weak keys, per-app), timeframes.
- ✅ **M4** — adaptive trainer (keybr loop seeded from real capture, persisted to trainer.json),
  five practice modes (trainer / weak spots / custom text / numbers / code), typing assists,
  sounds (bundled key-click sample), appearance modes, daily goal + streaks.
- ✅ **M5 (partial)** — Developer ID + notarization chain proven; release.yml builds, notarizes
  (app stapled first, then DMG), publishes on v* tags. Homebrew cask scaffolded.
- ⏳ **M2** — validate the injected-keystroke filter against real automation (Keyboard Maestro,
  Hammerspoon, `osascript`, text expanders, Copilot). Written + unit-tested, never field-tested.
- ⏳ Release chores: real VERSION/tag, README screenshots, repo public, patent search,
  key-click sample licensing (Epidemic Sound — owner decision).
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
      MotorFilter.swift            adaptive motor-vs-think split; per-transition thresholds
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

- **Releases are cut locally, not by CI.** The repo has no APPLE_* secrets, so release.yml
  fails on every tag and its publish step is gated off (it must never overwrite notarized
  assets with an unsigned DMG). Process: bump `VERSION` → `bash scripts/bundle-app.sh` →
  zip + `xcrun notarytool submit … --keychain-profile claudometer --wait` → staple the app →
  `SKIP_BUNDLE=1 bash scripts/make-dmg.sh` → notarize + staple the DMG → `cp` it to
  `dist/Fumble.dmg` → `gh release create vX.Y.Z dist/Fumble-X.Y.Z.dmg dist/Fumble.dmg` →
  bump version + sha256 in `alexiscodingbits/homebrew-fumble`. The site links
  `releases/latest/download/Fumble.dmg`, so **every release must attach `Fumble.dmg`** or the
  download button 404s.

- **Signing identity: a local self-signed "Fumble Local" cert keeps Input Monitoring across
  rebuilds.** macOS ties TCC permission to the signature; ad-hoc gets a new cdhash every build
  and wipes the grant. `bundle-app.sh` auto-uses the "Fumble Local" code-signing cert if present
  (create once: Keychain Access → Certificate Assistant → Create a Certificate, Code Signing,
  self-signed). It's untrusted-as-root, so `find-identity -v` hides it — the script greps without
  `-v` on purpose; codesign signs fine (trust matters for verifying, not signing). If a signature
  change ever orphans the grant, `tccutil reset ListenEvent com.alexiscodingbits.fumble` then
  re-grant.
- **Permission is watched, not checked once.** `AppCoordinator.beginPermissionWatch` polls every
  2s and self-starts capture the moment the grant lands — so granting in System Settings works
  without a relaunch, and the "Grant access" button is never a dead end. Don't revert this to a
  one-shot check: Input Monitoring grants don't notify a running app, and
  `CGPreflightListenEventAccess` can return a stale cached false, which made the app look
  permanently locked out even after the user said yes.
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
- **The motor-vs-think split is adaptive, per transition, not a flat cutoff** (`MotorFilter`).
  Threshold = clamp(k × your-own-median-for-this-transition, floor, ceiling), with a cascade
  transition → key → global → flat cold-start when a transition lacks history. The reference
  median is read from already-accepted samples (so it's clean) *before* the current sample is
  added (so there's no self-reference) — keep that ordering in `StatsRecorder`. `motorLatency`
  in `DayStats` is the running global pool that feeds the fallback; don't recompute it by
  merging key histograms. `fumble-cli` prints the per-tier breakdown — if real data is mostly
  `global`/`coldStart` rather than `transition`/`key`, the per-transition idea isn't paying off
  and the sample thresholds need revisiting. Defaults (k=4, floor=250ms, ceiling=3s,
  coldStart=600ms) are guesses to tune against real typing.
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
