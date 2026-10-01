import Foundation
import Testing
@testable import FumbleCore

/// Deterministic RNG (SplitMix64) so drill generation is reproducible in tests.
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

@Suite("DrillGenerator")
struct DrillGeneratorTests {

    private func keyCode(_ c: Character) -> Int { KeyIdentity.characterToKeyCode[c]! }

    @Test("generates the requested number of words from the pool")
    func count() {
        let generator = DrillGenerator(words: ["alpha", "bravo", "charlie", "delta"])
        var rng = SeededRNG(seed: 1)
        let drill = generator.generate(targets: .init(), wordCount: 10, using: &rng)
        let produced = drill.split(separator: " ")
        #expect(produced.count == 10)
        #expect(produced.allSatisfy { ["alpha", "bravo", "charlie", "delta"].contains(String($0)) })
    }

    @Test("no word repeats within a lesson while the pool has unused words")
    func noRepeats() {
        let pool = (0..<40).map { "word\($0)" }
        let generator = DrillGenerator(words: pool)
        for seed in UInt64(1)...20 {
            var rng = SeededRNG(seed: seed)
            let words = generator.generate(targets: .init(), wordCount: 30, using: &rng).split(separator: " ")
            #expect(Set(words).count == words.count)
        }
    }

    @Test("a pool smaller than the lesson cycles through every word before repeating")
    func exhaustedPoolCycles() {
        let generator = DrillGenerator(words: ["alpha", "bravo", "charlie"])
        var rng = SeededRNG(seed: 2)
        let words = generator.generate(targets: .init(), wordCount: 6, using: &rng).split(separator: " ")
        #expect(Set(words.prefix(3)).count == 3)
        #expect(Set(words.suffix(3)).count == 3)
    }

    @Test("scores words by the weak keys they contain")
    func scoresKeys() {
        let generator = DrillGenerator()
        let targets = DrillGenerator.Targets(keyCodes: [keyCode("z")])   // Z is weak
        #expect(generator.score("zebra", targets: targets) == 1)          // one z
        #expect(generator.score("pizza", targets: targets) == 2)          // two z's
        #expect(generator.score("water", targets: targets) == 0)          // no z
    }

    @Test("scores weak transitions higher than weak keys")
    func scoresBigrams() {
        var generator = DrillGenerator()
        generator.keyWeight = 1
        generator.bigramWeight = 3
        let th = BigramIdentity(first: KeyIdentity(keyCode: keyCode("t")), second: KeyIdentity(keyCode: keyCode("h")))
        let targets = DrillGenerator.Targets(keyCodes: [], bigrams: [th])
        #expect(generator.score("the", targets: targets) == 3)   // one t→h transition
        #expect(generator.score("cat", targets: targets) == 0)   // no t→h
    }

    @Test("weak-heavy words are sampled more often than neutral ones")
    func weightingSkewsSampling() {
        // Pool: one word full of the weak key among many without. Lessons are shorter than the
        // pool (sampling is without replacement), so the skew shows up as how often the weak
        // word makes it into a lesson at all.
        let neutral = (0..<40).map { "n\($0)" }
        let generator = DrillGenerator(words: ["zzz"] + neutral)
        let targets = DrillGenerator.Targets(keyCodes: [keyCode("z")])
        var zLessons = 0
        var neutralLessons = 0
        for seed in UInt64(1)...200 {
            var rng = SeededRNG(seed: seed)
            let words = Set(generator.generate(targets: targets, wordCount: 8, using: &rng).split(separator: " "))
            if words.contains("zzz") { zLessons += 1 }
            if words.contains("n0") { neutralLessons += 1 }
        }
        // "zzz" scores 3 (weight 4) vs 1 for a neutral word, so it should appear in clearly
        // more lessons than any single neutral word.
        #expect(zLessons > neutralLessons * 2)
    }

    @Test("no targets gives an unweighted but valid drill")
    func noTargets() {
        let generator = DrillGenerator()
        var rng = SeededRNG(seed: 7)
        let drill = generator.generate(targets: .init(), wordCount: 20, using: &rng)
        #expect(drill.split(separator: " ").count == 20)
    }

    @Test("same seed produces the same drill")
    func deterministic() {
        let generator = DrillGenerator()
        let targets = DrillGenerator.Targets(keyCodes: [keyCode("e"), keyCode("t")])
        var a = SeededRNG(seed: 99)
        var b = SeededRNG(seed: 99)
        #expect(generator.generate(targets: targets, wordCount: 15, using: &a)
                == generator.generate(targets: targets, wordCount: 15, using: &b))
    }

    @Test("Targets are pulled from the top of an analysis")
    func targetsFromAnalysis() {
        // A day where Z is clearly the worst key.
        var day = DayStats(date: Date(timeIntervalSince1970: 0))
        for keyCode in [0, 1, 2, 3, 5, 12, 13, 14] {
            var stat = KeyStat()
            for _ in 0..<100 { stat.latency.add(milliseconds: 90); stat.presses += 1 }
            day.keys[keyCode] = stat
            day.totalPresses += 100
        }
        var slow = KeyStat()
        for _ in 0..<100 { slow.latency.add(milliseconds: 320); slow.presses += 1 }
        day.keys[6] = slow   // Z
        day.totalPresses += 100
        day.activeSeconds = 900

        let analysis = WeakSpots.analyse(day)!
        let targets = DrillGenerator.Targets(analysis: analysis)
        #expect(targets.keyCodes.contains(6))
    }

    @Test("the shipped word pools are all typeable", arguments: [WordList.common, WordList.english])
    func poolIsTypeable(pool: [String]) {
        // Every character in the shipped pools must map to a key, or scoring silently misses it.
        for word in pool {
            for character in word {
                #expect(KeyIdentity.characterToKeyCode[character] != nil,
                        "‘\(character)’ in “\(word)” has no keycode mapping")
            }
        }
    }
}
