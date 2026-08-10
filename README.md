# Fumble

**A typing coach that already knows what you're bad at.**

Typing tutors make you grind synthetic drills for hours before they learn anything about you.
Fumble watches how you type all day — in your editor, your terminal, your email — and works out
which keys and which transitions actually cost you time. No cold start, and no pretending that
pseudo-random letter soup resembles the things you really type.

macOS menu bar. Free. Open source. Entirely on-device.

> **Status: early.** The tracker and the analysis are done and tested. Drills are next — see
> [Roadmap](#roadmap). Numbers are real; the app is young.

---

## Why not just use keybr?

keybr is good, and this exists because of two things it can't do:

1. **The cold start.** It only knows what you've typed *inside it*.
2. **The corpus.** It drills text generated from letter-frequency models. You don't type
   pseudo-English — you type `git commit -m`, `const`, `=>`, `];`, snake_case identifiers.
   The transitions that actually cost you time barely appear in its lessons.

Fumble measures the real thing.

## What it shows you

- **Honest WPM** — see [Honest numbers](#honest-numbers).
- **Weak keys**, ranked by *how much time they cost you today*, not by raw slowness.
- **Weak transitions** — the key pairs that hurt. `];` and `->` cost real time while the
  individual keys look fine.
- **Correction rate** per key — where you backspace most. Accuracy and speed are separate
  problems with separate fixes.
- **Per-app breakdown** — where the typing actually happens.

### Ranked by time cost, not by slowness

The headline metric is **seconds lost today**: how much slower than your own baseline a key is,
multiplied by how often you hit it.

This matters. A key you hit 50 times at +220ms costs you 11 seconds. A key you hit 2,000 times
at +40ms costs you 80 seconds. The second one is the problem, and "slowest key" ranking buries
it. "`;` cost you 80 seconds today" is also a claim you can accept or reject — which a composite
score with tuned weights would not be.

### Judged against you, not a target

Your baseline is the median of your own per-key p95 latencies. A 40 WPM typist and a 110 WPM
typist have completely different distributions; against a fixed threshold the slower typist's
entire keyboard reads as "weak", which is useless advice.

Per-key medians rather than all your keystrokes pooled, deliberately: pooling weights each key
by how often you press it, so a frequent slow key drags the baseline toward itself and hides its
own slowness. Those are exactly the keys worth fixing.

### Same-finger transitions are flagged, not drilled

`ed` is slow for everyone — it's one finger doing two jobs. Fumble shows these but keeps them out
of drills. Telling you to grind a same-finger bigram is telling you to fix your hand.

## Honest numbers

Most typing trackers will happily report 400 WPM when you paste a paragraph. Fumble excludes:

- **Software-injected keystrokes** — text expanders, automation (Hammerspoon, Keyboard Maestro,
  `osascript`), remote-control software, AI tools that type into the frontmost app. Hardware
  events carry `kCGEventSourceStateHIDSystemState`; anything posted by a process doesn't.
  (Pastes and most editor/LLM completions never generate keystrokes at all, so they can't
  inflate the count in the first place.)
- **Key autorepeat** — holding a key down is not typing.
- **Thinking pauses** — gaps over 600ms aren't finger movement, so they don't count as latency.
- **Idle time** — it never enters the WPM denominator.

Every one of these exclusions is **counted and shown** in the dropdown under "What was
excluded". The number should be auditable, not magic.

## Privacy

Fumble records **which key and when** — never the characters. What lands on disk is counters and
latency histograms with no ordering, so `cat` and `act` produce byte-identical files. Nothing is
recorded while a password field has focus. There is no network code, no account, no telemetry.

The full account, including the part that *is* a residual risk and what's done about it, is in
**[PRIVACY.md](PRIVACY.md)** — along with the commands to verify all of it yourself.

## Install

Requires macOS 14+.

```sh
git clone https://github.com/alexiscodingbits/Fumble.git
cd Fumble
bash scripts/bundle-app.sh
cp -R dist/Fumble.app /Applications/
open /Applications/Fumble.app
```

Grant **Input Monitoring** when prompted (System Settings → Privacy & Security → Input
Monitoring). Fumble cannot work without it, and cannot ship on the Mac App Store because of it:
the store mandates sandboxing, and sandboxing blocks this API.

> Builds are currently **ad-hoc signed**, so macOS will warn that the developer is
> unidentified, and Input Monitoring has to be re-granted after each rebuild. Notarized
> releases are on the roadmap.

## Inspect the data

```sh
cd FumbleCore
swift run fumble-cli            # today, summarised
swift run fumble-cli --all      # every day on record
swift run fumble-cli --json     # raw stored data, verbatim
```

## Roadmap

- [x] **M1** — capture core, latency histograms, per-key/bigram/app stats, persistence
- [x] **M3 (partial)** — weak-spot ranking and the dropdown UI
- [ ] **M2** — validate the injected-keystroke filter against real automation tools
- [ ] **M3** — keyboard heatmap, history and trends
- [ ] **M4** — **drills**: practice text generated from your own weak spots
- [ ] **M5** — notarized release, Homebrew cask, auto-update
- [ ] **v2** — the interesting one: **word- and token-level** coaching. Every tool in this space
      stops at individual keys and bigrams. Nothing knows that you fumble `useEffect` or
      `provenmetal` specifically. The plan is to build that vocabulary from your own repos and
      shell history and rank it with the timing data — so the word list comes from files already
      on your disk, and the keyboard tap never needs to see words at all.

## Development

```sh
cd FumbleCore
swift build        # must be 0 warnings
swift test         # 57 tests
```

Layout: `FumbleCore` is a pure Foundation model — no AppKit, no SwiftUI. `FumbleUI` is pure
presentation logic with no SwiftUI import, so the UI's *content* is unit-testable. `FumbleApp` is
the only target that touches SwiftUI/AppKit/CoreGraphics.

## Credits

The virtual-keycode table follows the Carbon `kVK_*` constants. Thanks to
[keyStats](https://github.com/debugtheworldbot/keyStats) (MIT) — read as prior art while working
out how to do system-wide capture on macOS.

## Licence

MIT — see [LICENSE](LICENSE).
