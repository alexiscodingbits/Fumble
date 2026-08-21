import Foundation

/// Generates lesson text for the adaptive trainer from a restricted set of unlocked letters,
/// heavily featuring the current focus letter — the same shape as keybr's lessons.
///
/// With only a few letters unlocked there aren't enough real words, so (like keybr) this makes
/// pronounceable pseudo-words: it alternates consonants and vowels for legibility and injects the
/// focus letter often, so you drill the weak one in varied surroundings rather than in isolation.
///
/// When a `naturalWords` pool is supplied, real words spelled entirely from the unlocked letters
/// are blended in (keybr's "Prefer natural words"). This matters most for rare focus letters:
/// pseudo-words for `q` degenerate into "qqlqq muqq", whereas the natural pool offers "quick",
/// "quote", "unique" — the same drill, but text a human can actually read.
public enum TrainerLessonGenerator {

    /// Roughly how often any given position is forced to the focus letter.
    static let focusBias = 0.33

    /// The natural path needs at least this many focus-containing real words before it fully
    /// replaces pseudo-words. Below it, natural and pseudo words are mixed in proportion —
    /// a pool of 5 gives ~50% natural — so thin pools blend rather than cliff into repetition.
    static let minimumFocusPool = 10

    /// Without a focus letter there's no thinness to blend against, so it's a simple switch:
    /// enough real words to avoid obvious repetition, or all pseudo-words.
    static let minimumGeneralPool = 15

    public static func generate<R: RandomNumberGenerator>(
        unlocked: [KeyIdentity],
        focus: KeyIdentity?,
        wordCount: Int = 24,
        naturalWords: [String] = [],
        using rng: inout R
    ) -> String {
        let letters = unlocked.filter { KeyIdentity.labels[$0.keyCode]?.count == 1 }
        guard wordCount > 0, !letters.isEmpty else { return "" }

        let vowels = letters.filter(\.isVowel)
        let consonants = letters.filter { !$0.isVowel }

        // Natural pools: real words spelled entirely from unlocked letters, split on whether
        // they contain the focus letter. The invariant that only unlocked letters ever appear
        // is enforced here by the filter, not trusted from the caller's word list.
        let unlockedChars = Set(letters.map { Character($0.label.lowercased()) })
        let naturalPool = naturalWords.filter { word in
            !word.isEmpty && word.allSatisfy { unlockedChars.contains($0) }
        }
        let focusChar = focus.flatMap { key in
            KeyIdentity.labels[key.keyCode].map { Character($0.lowercased()) }
        }
        let focusPool = focusChar.map { c in naturalPool.filter { $0.contains(c) } } ?? []
        let plainPool = focusChar.map { c in naturalPool.filter { !$0.contains(c) } } ?? naturalPool

        // Per-slot probability of drawing a real word instead of a pseudo-word.
        let naturalShare: Double
        if focusChar != nil {
            naturalShare = min(1, Double(focusPool.count) / Double(minimumFocusPool))
        } else {
            naturalShare = naturalPool.count >= minimumGeneralPool ? 1 : 0
        }

        var words: [String] = []
        words.reserveCapacity(wordCount)
        var lastWord: String?

        for _ in 0..<wordCount {
            let natural = naturalShare > 0 && Double.random(in: 0..<1, using: &rng) < naturalShare
            let word: String
            if natural {
                word = naturalWord(
                    focusPool: focusPool, plainPool: plainPool, avoiding: lastWord, using: &rng
                )
            } else {
                word = pseudoWord(
                    focus: focus, vowels: vowels, consonants: consonants, letters: letters,
                    using: &rng
                )
            }
            if !word.isEmpty {
                words.append(word)
                lastWord = word
            }
        }
        return words.joined(separator: " ")
    }

    /// Pick one real word. With a focus letter, roughly half the picks come from the
    /// focus-containing pool so the weak letter stays featured; the rest come from the general
    /// pool so the lesson still reads like language rather than a q-word litany.
    private static func naturalWord<R: RandomNumberGenerator>(
        focusPool: [String],
        plainPool: [String],
        avoiding lastWord: String?,
        using rng: inout R
    ) -> String {
        let wantFocus = !focusPool.isEmpty
            && (plainPool.isEmpty || Double.random(in: 0..<1, using: &rng) < 0.5)
        let pool = wantFocus ? focusPool : plainPool
        guard var word = pool.randomElement(using: &rng) else { return "" }
        // One redraw avoids most immediate repeats without stalling on thin pools.
        if word == lastWord, pool.count > 1 {
            word = pool.randomElement(using: &rng) ?? word
        }
        return word
    }

    /// The original keybr-style generator: one pronounceable pseudo-word from the unlocked
    /// letters, biased toward the focus letter.
    private static func pseudoWord<R: RandomNumberGenerator>(
        focus: KeyIdentity?,
        vowels: [KeyIdentity],
        consonants: [KeyIdentity],
        letters: [KeyIdentity],
        using rng: inout R
    ) -> String {
        let length = Int.random(in: 3...5, using: &rng)
        var word = ""
        for position in 0..<length {
            let key = pickKey(
                position: position, focus: focus,
                vowels: vowels, consonants: consonants, letters: letters, using: &rng
            )
            if let label = KeyIdentity.labels[key.keyCode] {
                word.append(Character(label.lowercased()))
            }
        }
        return word
    }

    private static func pickKey<R: RandomNumberGenerator>(
        position: Int,
        focus: KeyIdentity?,
        vowels: [KeyIdentity],
        consonants: [KeyIdentity],
        letters: [KeyIdentity],
        using rng: inout R
    ) -> KeyIdentity {
        // Feature the focus letter often, so the weak key gets drilled in many contexts.
        if let focus, Double.random(in: 0...1, using: &rng) < focusBias {
            return focus
        }
        // Alternate consonant/vowel for pronounceability when both are available.
        if !vowels.isEmpty, !consonants.isEmpty {
            let pool = position.isMultiple(of: 2) ? consonants : vowels
            return pool.randomElement(using: &rng) ?? letters[0]
        }
        return letters.randomElement(using: &rng) ?? letters[0]
    }
}
