#!/usr/bin/env python3
"""Regenerate FumbleCore/Sources/FumbleCore/WordListData.swift from SCOWL.

Usage: scripts/gen-wordlist.py /path/to/scowl-2020.12.07
(tarball: https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz)

core = SCOWL english-words.{10,20} + HAND_PICKED, minus anything in the US or UK variant lists.
us / uk = american-words.{10,20} / british-words.{10,20}, each minus the other.
Only lowercase a–z words of 2+ letters are kept; the trainer filters letter by letter.
"""
import io, re, sys, pathlib

# Rare-letter words kept from Fumble's original hand-written list, so q/z/x/j lessons stay rich
# even if a future SCOWL drop thins them out.
HAND_PICKED = """
banjo banquet blaze boxer bronze buzz conquer dizzy eloquent equator fox gaze
graze hazel headquarters internet jar jasmine jersey jewel jingle jockey jog juggle
jumbo majestic mosquito opaque oven oxide pixel plaza proxy quaint quart quartz
quench quilt rejoice salad seize sneeze squirrel textile toolbox toxic vortex wax
zebra zest zigzag zinc zipper zoo
""".split()

def load(final, name):
    text = io.open(final / name, encoding="latin-1").read()
    return {w for w in text.split("\n") if re.fullmatch(r"[a-z]{2,}", w)}

def main(root):
    final = pathlib.Path(root) / "final"
    scowl = load(final, "english-words.10") | load(final, "english-words.20")
    us = load(final, "american-words.10") | load(final, "american-words.20")
    uk = load(final, "british-words.10") | load(final, "british-words.20")
    variants = us | uk
    core = sorted((scowl | set(HAND_PICKED)) - variants)
    us_only, uk_only = sorted(us - uk), sorted(uk - us)
    assert "color" in us_only and "colour" in uk_only and "color" not in core

    def lit(words): return "\n".join(words)
    out = f'''// GENERATED — do not edit by hand. Regenerate with scripts/gen-wordlist.py.
//
// Source: SCOWL (Spell Checker Oriented Word Lists) 2020.12.07, size levels 10 + 20 —
// the ~11k most common English words — plus Fumble's hand-picked rare-letter words.
// Lowercase a–z only, 2+ letters. Regional spellings are split out so the app can offer
// US or UK English; `core` contains no word whose spelling differs between the two.
//
// SCOWL is Copyright 2000-2018 Kevin Atkinson, used under its permissive licence.
// Full notice: THIRD_PARTY_NOTICES.md at the repo root.

enum WordListData {{
    /// Words spelled the same in US and UK English. One per line.
    static let core = """
{lit(core)}
"""

    /// US spellings (color, organize, center …).
    static let us = """
{lit(us_only)}
"""

    /// UK spellings (colour, organise, centre …).
    static let uk = """
{lit(uk_only)}
"""
}}
'''
    target = pathlib.Path(__file__).resolve().parents[1] / "FumbleCore/Sources/FumbleCore/WordListData.swift"
    target.write_text(out)
    print(f"core {len(core)}  us {len(us_only)}  uk {len(uk_only)} → {target}")

if __name__ == "__main__":
    main(sys.argv[1])
