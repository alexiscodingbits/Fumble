import Foundation
import Testing
@testable import FumbleCore

/// Deterministic RNG (SplitMix64) so lesson generation is reproducible in tests.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("WordList.english")
struct WordListEnglishTests {

    @Test("is strictly lowercase a-z")
    func strictlyLowercaseAZ() {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz")
        for word in WordList.english(spelling: .us) + WordList.english(spelling: .uk) {
            #expect(word.allSatisfy { allowed.contains($0) },
                    "“\(word)” contains a character outside a-z")
        }
    }

    @Test("is deduplicated")
    func deduplicated() {
        #expect(Set(WordList.english).count == WordList.english.count)
    }

    @Test("is a large pool")
    func size() {
        #expect((9_000...14_000).contains(WordList.english.count))
    }

    @Test("US and UK pools carry their own spellings and none of the other's")
    func regionalSpellings() {
        let us = Set(WordList.english(spelling: .us))
        let uk = Set(WordList.english(spelling: .uk))
        for (american, british) in [("color", "colour"), ("organize", "organise"),
                                    ("center", "centre"), ("gray", "grey")] {
            #expect(us.contains(american) && !us.contains(british), "\(american)/\(british) in US pool")
            #expect(uk.contains(british) && !uk.contains(american), "\(american)/\(british) in UK pool")
        }
        // Shared words are in both; the pools differ only by the spelling variants.
        #expect(us.contains("keyboard") && uk.contains("keyboard"))
    }

    @Test("covers the rare letters with real words")
    func rareLetterCoverage() {
        // The natural-words blend needs enough q/z/x/j words that a rare focus letter still
        // finds a usable pool (>= TrainerLessonGenerator.minimumFocusPool once the letter set
        // widens) — otherwise rare letters fall straight back to pseudo-word soup.
        for letter in "qzxj" {
            let count = WordList.english.filter { $0.contains(letter) }.count
            #expect(count >= 10, "only \(count) words contain ‘\(letter)’")
        }
    }
}

@Suite("NumberLessonGenerator")
struct NumberLessonGeneratorTests {

    @Test("produces the requested number of digit groups, each 3-6 digits")
    func groupShape() {
        var rng = SeededRNG(seed: 4)
        let text = NumberLessonGenerator.generate(groupCount: 50, using: &rng)
        let groups = text.split(separator: " ")
        #expect(groups.count == 50)
        for group in groups {
            #expect((3...6).contains(group.count))
            #expect(group.allSatisfy { $0.isNumber })
        }
    }

    @Test("leading digits follow Benford's law: 1s dominate 9s")
    func benfordLeadingDigits() {
        var rng = SeededRNG(seed: 21)
        let text = NumberLessonGenerator.generate(groupCount: 3000, using: &rng)
        let leading = text.split(separator: " ").compactMap(\.first)
        let ones = leading.filter { $0 == "1" }.count
        let nines = leading.filter { $0 == "9" }.count
        // Benford predicts p(1)=0.301 vs p(9)=0.046, a 6.6x ratio; 3x leaves plenty of
        // headroom for sampling noise at n=3000.
        #expect(nines > 0)   // 9 must still occur — it's a skew, not an exclusion
        #expect(ones >= 3 * nines)
    }

    @Test("never emits a leading zero")
    func noLeadingZero() {
        var rng = SeededRNG(seed: 8)
        let text = NumberLessonGenerator.generate(groupCount: 500, using: &rng)
        #expect(text.split(separator: " ").allSatisfy { $0.first != "0" })
    }

    @Test("same seed produces the same lesson")
    func deterministic() {
        var a = SeededRNG(seed: 77)
        var b = SeededRNG(seed: 77)
        #expect(NumberLessonGenerator.generate(groupCount: 30, using: &a)
                == NumberLessonGenerator.generate(groupCount: 30, using: &b))
    }

    @Test("zero groups yields empty text")
    func zeroGroups() {
        var rng = SeededRNG(seed: 1)
        #expect(NumberLessonGenerator.generate(groupCount: 0, using: &rng) == "")
    }
}

@Suite("CodeLessonGenerator")
struct CodeLessonGeneratorTests {

    @Test("every character maps to a physical key or is a space")
    func allCharactersTypeable() {
        // The drill surface scores against keycodes; a character with no mapping (any shifted
        // symbol) would be impossible to complete. This is the load-bearing constraint on the
        // template set.
        var rng = SeededRNG(seed: 13)
        let text = CodeLessonGenerator.generate(lineCount: 60, using: &rng)
        for character in text {
            #expect(character == " " || KeyIdentity.characterToKeyCode[character] != nil,
                    "‘\(character)’ has no keycode mapping")
        }
    }

    @Test("contains no newlines — the drill surface can't type Return")
    func noNewlines() {
        var rng = SeededRNG(seed: 2)
        let text = CodeLessonGenerator.generate(lineCount: 40, using: &rng)
        #expect(!text.contains("\n") && !text.contains("\r"))
    }

    @Test("produces the requested number of fragments")
    func fragmentCount() {
        // Every template contains exactly one `;`, so the semicolon count is the fragment count.
        var rng = SeededRNG(seed: 9)
        let text = CodeLessonGenerator.generate(lineCount: 25, using: &rng)
        #expect(text.filter { $0 == ";" }.count == 25)
    }

    @Test("no placeholder survives identifier substitution")
    func placeholdersFilled() {
        var rng = SeededRNG(seed: 6)
        let text = CodeLessonGenerator.generate(lineCount: 60, using: &rng)
        #expect(!text.contains("@"))
    }

    @Test("identifiers vary across the lesson")
    func identifiersVary() {
        var rng = SeededRNG(seed: 30)
        let text = CodeLessonGenerator.generate(lineCount: 60, using: &rng)
        let used = CodeLessonGenerator.identifiers.filter { text.contains($0) }
        // 60 fragments with 2-3 slots each should easily touch several of the 18 identifiers.
        #expect(used.count >= 5)
    }

    @Test("same seed produces the same lesson")
    func deterministic() {
        var a = SeededRNG(seed: 55)
        var b = SeededRNG(seed: 55)
        #expect(CodeLessonGenerator.generate(lineCount: 20, using: &a)
                == CodeLessonGenerator.generate(lineCount: 20, using: &b))
    }

    @Test("zero lines yields empty text")
    func zeroLines() {
        var rng = SeededRNG(seed: 1)
        #expect(CodeLessonGenerator.generate(lineCount: 0, using: &rng) == "")
    }
}

@Suite("CustomTextLesson")
struct CustomTextLessonTests {

    @Test("smart quotes become straight quotes")
    func smartQuotes() {
        // Curly doubles normalise to `"`, which then dies in the typeability filter (it's
        // Shift+' — no keycode entry); curly singles normalise to the typeable `'`.
        let words = CustomTextLesson.words(
            from: "\u{201C}Hello\u{201D} \u{2018}world\u{2019}",
            removePunctuation: false, lowercase: false
        )
        #expect(words == ["Hello", "'world'"])
    }

    @Test("en and em dashes become hyphens")
    func dashes() {
        let words = CustomTextLesson.words(
            from: "pages 3\u{2013}5 and a well\u{2014}known fact",
            removePunctuation: false, lowercase: false
        )
        #expect(words == ["pages", "3-5", "and", "a", "well-known", "fact"])
    }

    @Test("all whitespace collapses into word boundaries")
    func whitespaceCollapse() {
        let words = CustomTextLesson.words(
            from: "one\ntwo\r\n\tthree   four\u{00A0}five",
            removePunctuation: false, lowercase: false
        )
        #expect(words == ["one", "two", "three", "four", "five"])
    }

    @Test("untypeable characters are stripped, not kept as gaps")
    func stripsUntypeable() {
        let words = CustomTextLesson.words(
            from: "good \u{1F44D} job caf\u{E9}",
            removePunctuation: false, lowercase: false
        )
        // The emoji token vanishes entirely; the accented é is stripped from within its word.
        #expect(words == ["good", "job", "caf"])
    }

    @Test("removePunctuation strips punctuation but keeps letters and digits")
    func removePunctuation() {
        let words = CustomTextLesson.words(
            from: "don't stop, now. item[3];",
            removePunctuation: true, lowercase: false
        )
        #expect(words == ["dont", "stop", "now", "item3"])
    }

    @Test("punctuation is kept when not stripping")
    func keepsPunctuation() {
        let words = CustomTextLesson.words(
            from: "don't stop, now.",
            removePunctuation: false, lowercase: false
        )
        #expect(words == ["don't", "stop,", "now."])
    }

    @Test("lowercase option folds case; without it Shift-typeable capitals survive")
    func lowercaseOption() {
        let text = "Hello WORLD"
        #expect(CustomTextLesson.words(from: text, removePunctuation: false, lowercase: true)
                == ["hello", "world"])
        #expect(CustomTextLesson.words(from: text, removePunctuation: false, lowercase: false)
                == ["Hello", "WORLD"])
    }

    @Test("tokens that clean away to nothing are dropped")
    func dropsEmptyTokens() {
        #expect(CustomTextLesson.words(from: "\u{1F389} \u{1F680}",
                                       removePunctuation: false, lowercase: false) == [])
        #expect(CustomTextLesson.words(from: "", removePunctuation: true, lowercase: true) == [])
    }

    @Test("pasted multi-line prose with unicode junk comes out clean")
    func multiLinePaste() {
        let pasted = """
        \u{201C}Smart quotes\u{201D} and \u{2018}apostrophes\u{2019} \u{2014} plus emoji \u{1F389}\u{1F680}
        a second\tline with tabs
        """
        let words = CustomTextLesson.words(from: pasted, removePunctuation: true, lowercase: true)
        #expect(words == ["smart", "quotes", "and", "apostrophes", "plus", "emoji",
                          "a", "second", "line", "with", "tabs"])
    }
}
