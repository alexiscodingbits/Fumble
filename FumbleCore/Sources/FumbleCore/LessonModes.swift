import Foundation

/// Alternative lesson content for the practice window: number drills, code-shaped drills, and
/// user-pasted custom text. All pure functions with injected RNGs, like the other generators,
/// so every mode is deterministic under test.

// MARK: - Numbers

/// Space-separated groups of digits for number-row practice.
public enum NumberLessonGenerator {

    /// Cumulative Benford distribution for the leading digit: p(d) = log10(1 + 1/d).
    /// Real-world numbers (prices, line counts, timestamps) start with 1 about 30% of the time
    /// and with 9 under 5%, so a drill that samples leading digits uniformly would practise a
    /// distribution nobody actually types. The product sum telescopes to log10(10) = 1 exactly.
    static let leadingDigitCumulative: [Double] = {
        var bounds: [Double] = []
        var total = 0.0
        for digit in 1...9 {
            total += log10(1 + 1 / Double(digit))
            bounds.append(total)
        }
        return bounds
    }()

    public static func generate<R: RandomNumberGenerator>(
        groupCount: Int,
        using rng: inout R
    ) -> String {
        guard groupCount > 0 else { return "" }

        var groups: [String] = []
        groups.reserveCapacity(groupCount)
        for _ in 0..<groupCount {
            let length = Int.random(in: 3...6, using: &rng)
            var group = String(leadingDigit(using: &rng))
            // Only the leading digit is Benford-distributed; later positions of real numbers
            // are close to uniform, and that's also what spreads practice across all ten keys.
            for _ in 1..<length {
                group += String(Int.random(in: 0...9, using: &rng))
            }
            groups.append(group)
        }
        return groups.joined(separator: " ")
    }

    private static func leadingDigit<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        let roll = Double.random(in: 0..<1, using: &rng)
        for (index, bound) in leadingDigitCumulative.enumerated() where roll < bound {
            return index + 1
        }
        return 9   // roll landed on the last bound's floating-point shortfall
    }
}

// MARK: - Code

/// Generic code-shaped fragments for symbol practice.
public enum CodeLessonGenerator {

    /// Fragment templates; `@1`/`@2`/`@3` are identifier slots filled from `identifiers`.
    ///
    /// Restricted to **unshifted** ANSI characters on purpose: the drill scores against
    /// physical keycodes via `KeyIdentity.characterToKeyCode`, which has no entries for
    /// shifted symbols (`(`, `{`, `*`, `"`, `+` …). So the fragments lean on `=`, `;`,
    /// brackets, dots, quotes and slashes — still unmistakably code-shaped, and every
    /// character maps to a key. Each template contains exactly one `;` so a fragment count
    /// is recoverable from the output. No newlines: the drill surface can't type Return,
    /// so fragments are joined by single spaces.
    static let templates: [String] = [
        "let @1 = @2[@3];",
        "var @1 = @2.@3;",
        "@1.@2 = @3;",
        "return @1[@3];",
        "@1 = '@2';",
        "import @1.@2;",
        "@1 = [@2, @3];",
        "@1 = @2 - 1;",
        "@1 = @2 / @3;",
        "let @1 = `@2`;",
        "@1, @2 = @2, @1;",
        "@1 = @2[@3].@1;",
    ]

    /// Short, code-flavoured identifiers. Lowercase only — uppercase letters would need Shift
    /// and aren't in `characterToKeyCode`.
    static let identifiers: [String] = [
        "x", "y", "i", "j", "k", "n", "arr", "buf", "count", "data",
        "idx", "item", "key", "list", "node", "result", "temp", "value",
    ]

    public static func generate<R: RandomNumberGenerator>(
        lineCount: Int,
        using rng: inout R
    ) -> String {
        guard lineCount > 0 else { return "" }

        var fragments: [String] = []
        fragments.reserveCapacity(lineCount)
        var lastTemplate: String?

        for _ in 0..<lineCount {
            var template = templates.randomElement(using: &rng) ?? templates[0]
            // One redraw avoids most back-to-back repeats of the same shape.
            if template == lastTemplate, templates.count > 1 {
                template = templates.randomElement(using: &rng) ?? template
            }
            lastTemplate = template

            var fragment = template
            for slot in ["@1", "@2", "@3"] {
                let identifier = identifiers.randomElement(using: &rng) ?? identifiers[0]
                fragment = fragment.replacingOccurrences(of: slot, with: identifier)
            }
            fragments.append(fragment)
        }
        return fragments.joined(separator: " ")
    }
}

// MARK: - Custom text

/// Turns arbitrary pasted text into drillable words.
///
/// Pasted prose arrives full of things the drill surface can't score: curly quotes, em dashes,
/// emoji, accents, hard-wrapped lines. This normalises the typography back to plain ASCII,
/// then strips anything that still doesn't map to a physical key.
public enum CustomTextLesson {

    public static func words(
        from text: String,
        removePunctuation: Bool,
        lowercase: Bool
    ) -> [String] {
        // 1. Typography → ASCII, so "smart" characters become their typeable equivalents
        //    instead of being silently dropped in step 3.
        var normalized = ""
        normalized.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\u{2018}", "\u{2019}", "\u{201B}":   // ‘ ’ ‛
                normalized.append("'")
            case "\u{201C}", "\u{201D}", "\u{201E}":   // “ ” „
                normalized.append("\"")
            case "\u{2013}", "\u{2014}":               // – —
                normalized.append("-")
            default:
                normalized.append(character)
            }
        }

        // 2. Collapse all whitespace — spaces, tabs, newlines — into token boundaries.
        let tokens = normalized.split(whereSeparator: \.isWhitespace)

        // 3. Per-character cleanup inside each token; empty leftovers are dropped, not kept
        //    as blank words. (Straight double quotes die here too: `"` is Shift+', so it has
        //    no keycode entry — normalising it first just keeps this step the single filter.)
        var words: [String] = []
        words.reserveCapacity(tokens.count)
        for token in tokens {
            var cleaned = ""
            for character in token {
                guard isTypeable(character) else { continue }
                if removePunctuation, !character.isLetter, !character.isNumber { continue }
                cleaned.append(character)
            }
            if lowercase { cleaned = cleaned.lowercased() }
            if !cleaned.isEmpty { words.append(cleaned) }
        }
        return words
    }

    /// Typeable ignoring case: `A` reaches the same physical key as `a` via Shift.
    private static func isTypeable(_ character: Character) -> Bool {
        let lowered = String(character).lowercased()
        // Lowercasing can expand some exotic characters into several; those aren't typeable.
        guard lowered.count == 1, let single = lowered.first else { return false }
        return KeyIdentity.characterToKeyCode[single] != nil
    }
}
