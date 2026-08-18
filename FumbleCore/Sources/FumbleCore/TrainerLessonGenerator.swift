import Foundation

/// Generates lesson text for the adaptive trainer from a restricted set of unlocked letters,
/// heavily featuring the current focus letter — the same shape as keybr's lessons.
///
/// With only a few letters unlocked there aren't enough real words, so (like keybr) this makes
/// pronounceable pseudo-words: it alternates consonants and vowels for legibility and injects the
/// focus letter often, so you drill the weak one in varied surroundings rather than in isolation.
public enum TrainerLessonGenerator {

    /// Roughly how often any given position is forced to the focus letter.
    static let focusBias = 0.33

    public static func generate<R: RandomNumberGenerator>(
        unlocked: [KeyIdentity],
        focus: KeyIdentity?,
        wordCount: Int = 24,
        using rng: inout R
    ) -> String {
        let letters = unlocked.filter { KeyIdentity.labels[$0.keyCode]?.count == 1 }
        guard wordCount > 0, !letters.isEmpty else { return "" }

        let vowels = letters.filter(\.isVowel)
        let consonants = letters.filter { !$0.isVowel }

        var words: [String] = []
        words.reserveCapacity(wordCount)

        for _ in 0..<wordCount {
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
            if !word.isEmpty { words.append(word) }
        }
        return words.joined(separator: " ")
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
