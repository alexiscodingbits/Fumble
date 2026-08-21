# Privacy

Fumble watches your keyboard. That is the product, so this document is specific about what
that means, and the claims here are checkable — see [Verify it yourself](#verify-it-yourself).

## What is recorded

For each keystroke, Fumble records **which physical key** and **when**, updates a set of
counters, and throws the event away. What ends up on disk is:

```
key    presses  corrections  latency histogram
;        1,204            9  [ … 28 bucket counts … ]
z          412           37  [ … 28 bucket counts … ]

bigram  count  latency histogram
];        340  [ … ]
```

Plus daily totals, active-typing seconds, and per-application press counts (bundle
identifiers like `com.apple.Terminal`).

## What is not recorded

- **No characters.** Fumble stores the *keycode* of the physical key, never the character it
  produced. Resolving keycode → character would require reading your keyboard layout and
  modifier state — that is, reconstructing your text. Fumble does not do it.
- **No sequence.** Counters have no order. Typing `cat` and typing `act` produce byte-identical
  key counters. There is no buffer of recent keystrokes, nothing queued, nothing to flush.
- **No passwords.** While a secure input field has focus, keystrokes are discarded before
  anything is counted. macOS tells us when this is the case (`IsSecureEventInputEnabled`).
- **No network.** Fumble makes no network requests. There is no account, no sync, no telemetry,
  no crash reporting. This is enforced by there being no networking code in the app.

## The honest part

A bigram table is a partial n-gram model of your writing, and rare n-grams are the identifying
ones. If you type an unusual identifier a handful of times, it would show up as an anomalous
low-count entry that someone with the file could partially infer.

So rare bigrams are **not written to disk**. Anything seen fewer than three times in a day is
dropped when the day is saved. That removes precisely the entries carrying recoverable
information, and it costs nothing analytically — a two-sample latency estimate was never
usable. The threshold is `RecorderConfig.minimumBigramCount`.

This does not make the remaining data zero-information. Common bigram frequencies say something
about what language you write in and roughly what kind of text. It is a long way from your
sentences, and we would rather describe the residue accurately than claim it is nothing.

## Read-only by construction

The keyboard tap is created with `CGEventTapOptions.listenOnly`. The process **cannot** modify,
swallow, or inject keystrokes — that is enforced by macOS, not by our own good intentions.

## Where the data lives

```
~/Library/Application Support/Fumble/days/YYYY-MM-DD.json   # daily counters + histograms
~/Library/Application Support/Fumble/trainer.json           # trainer progress (per-key WPM, unlocked letters)
~/Library/Application Support/Fumble/custom-text.txt        # only if you use Custom-text practice (see below)
```

Plus, in the app's standard preferences (`defaults`): your settings, and a per-day tally of
practice **minutes** (a number per date — no content).

`custom-text.txt` exists only if you paste text into the Custom-text practice mode, and it is
your pasted text verbatim — that's the feature. It is never transmitted anywhere, it's a plain
file you can read and delete, and it is included in "Delete all data".

**"Delete all data" removes all of it**: the day files, the trainer progress, the custom text,
and the practice-time tally.

## Practice typing is excluded

Keystrokes typed inside Fumble's own practice window are dropped before any counter moves
(counted visibly as "Practice typing" in the diagnostics). Drill text is synthetic and aimed at
your weak keys — letting it into the day would corrupt the very model that generated it.

## Verify it yourself

Don't take the above on trust:

```sh
# Print everything stored for today, exactly as it exists on disk.
fumble-cli --json

# Or just read the file.
cat ~/Library/Application\ Support/Fumble/days/$(date +%F).json
```

You will find counters and histograms. You will not find your text — because it was never
written down.

For the network claim, run Fumble and watch it with Little Snitch, or:

```sh
lsof -i -a -p "$(pgrep -x Fumble)"
```

## Permission

Fumble needs **Input Monitoring** (System Settings → Privacy & Security → Input Monitoring).
That is the permission that lets a process observe keystrokes system-wide. There is no way to
build this app without it, which is also why Fumble cannot ship on the Mac App Store: the store
mandates sandboxing, and sandboxing blocks this API.
