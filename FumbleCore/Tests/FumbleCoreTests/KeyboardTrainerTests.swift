import Foundation
import Testing
@testable import FumbleCore

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

@Suite("KeyboardTrainer")
struct KeyboardTrainerTests {

    private func code(_ c: Character) -> Int { KeyIdentity.characterToKeyCode[c]! }

    @Test("a blank-slate learner starts with the minimum letters focused on the first")
    func coldStart() {
        let trainer = KeyboardTrainer(seed: [:])
        #expect(trainer.unlockedKeys.count == KeyboardTrainer.Config().minimumUnlocked)
        // With no data every letter is at the floor, so focus is the first frequency letter, 'e'.
        #expect(trainer.focusKey?.label == "E")
    }

    @Test("seeding from real data opens straight onto the first real weakness")
    func seededSkipsMasteredLetters() {
        // Fast on the top frequency letters (e t a o i n s h), slow on 'r'.
        var seed: [Int: Double] = [:]
        for c in "etaoinsh" { seed[code(c)] = 90 }   // well above target
        seed[code("r")] = 20                          // the weak one

        let trainer = KeyboardTrainer(seed: seed)
        // The mastered leading run is unlocked, and focus lands on the first non-mastered
        // letter in frequency order — 'r' — not back on the home row.
        #expect(trainer.focusKey?.label == "R")
        #expect(trainer.isMastered(KeyIdentity(keyCode: code("e"))))
    }

    @Test("confidence maps WPM onto 0...1 against the target")
    func confidenceMapping() {
        var config = KeyboardTrainer.Config()
        config.targetWPM = 35
        config.floorWPM = 12
        let trainer = KeyboardTrainer(seed: [code("e"): 35, code("t"): 12, code("a"): 23.5], config: config)
        #expect(trainer.confidence(for: KeyIdentity(keyCode: code("e"))) == 1)
        #expect(trainer.confidence(for: KeyIdentity(keyCode: code("t"))) == 0)
        #expect(abs(trainer.confidence(for: KeyIdentity(keyCode: code("a"))) - 0.5) < 0.02)
    }

    @Test("mastering every unlocked letter unlocks the next one")
    func unlockOnMastery() {
        let trainer = KeyboardTrainer(seed: [:])
        let before = trainer.unlockedCount
        // Report every unlocked letter as well above target.
        let mastered = Dictionary(uniqueKeysWithValues: trainer.unlockedKeys.map { ($0.keyCode, 80.0) })
        trainer.record(perKeyWPM: mastered)
        #expect(trainer.unlockedCount == before + 1)
    }

    @Test("a weak letter blocks further unlocks")
    func weakLetterBlocksUnlock() {
        let trainer = KeyboardTrainer(seed: [:])
        let before = trainer.unlockedCount
        var results = Dictionary(uniqueKeysWithValues: trainer.unlockedKeys.map { ($0.keyCode, 80.0) })
        results[trainer.unlockedKeys[2].keyCode] = 15   // one still slow
        trainer.record(perKeyWPM: results)
        #expect(trainer.unlockedCount == before)   // no unlock while one lags
    }

    @Test("confidence updates as a smoothed running value, not a jump")
    func smoothedConfidence() {
        var config = KeyboardTrainer.Config()
        config.blend = 0.3
        let trainer = KeyboardTrainer(seed: [code("e"): 20], config: config)
        trainer.record(perKeyWPM: [code("e"): 40])
        let w = trainer.wpm[code("e")]!
        // 20 + (40-20)*0.3 = 26, not a jump to 40.
        #expect(abs(w - 26) < 0.001)
    }

    @Test("the whole alphabet can be completed")
    func completion() {
        // Seed every letter above target: fully mastered from the start.
        var seed: [Int: Double] = [:]
        for key in KeyIdentity.alphabetByFrequency { seed[key.keyCode] = 100 }
        let trainer = KeyboardTrainer(seed: seed)
        // Drive unlocks to the end.
        for _ in 0..<30 {
            trainer.record(perKeyWPM: Dictionary(uniqueKeysWithValues: trainer.unlockedKeys.map { ($0.keyCode, 100.0) }))
        }
        #expect(trainer.isComplete)
        #expect(trainer.focusKey == nil)
    }
}

@Suite("TrainerLessonGenerator")
struct TrainerLessonGeneratorTests {

    private func code(_ c: Character) -> Int { KeyIdentity.characterToKeyCode[c]! }
    private func keys(_ s: String) -> [KeyIdentity] { s.map { KeyIdentity(keyCode: code($0)) } }

    @Test("only uses unlocked letters")
    func onlyUnlocked() {
        let unlocked = keys("etao")
        var rng = SeededRNG(seed: 3)
        let text = TrainerLessonGenerator.generate(unlocked: unlocked, focus: nil, wordCount: 30, using: &rng)
        let allowed = Set("etao ")
        #expect(text.allSatisfy { allowed.contains($0) })
    }

    @Test("features the focus letter heavily")
    func featuresFocus() {
        let unlocked = keys("etaoinsr")
        let focus = KeyIdentity(keyCode: code("r"))
        var rng = SeededRNG(seed: 11)
        let text = TrainerLessonGenerator.generate(unlocked: unlocked, focus: focus, wordCount: 40, using: &rng)
        let words = text.split(separator: " ")
        let withFocus = words.filter { $0.contains("r") }.count
        // The focus letter should appear in a large share of words.
        #expect(Double(withFocus) / Double(words.count) > 0.6)
    }

    @Test("produces the requested word count")
    func wordCount() {
        var rng = SeededRNG(seed: 5)
        let text = TrainerLessonGenerator.generate(unlocked: keys("etaoin"), focus: nil, wordCount: 20, using: &rng)
        #expect(text.split(separator: " ").count == 20)
    }

    @Test("empty unlocked set yields empty text")
    func emptyUnlocked() {
        var rng = SeededRNG(seed: 1)
        #expect(TrainerLessonGenerator.generate(unlocked: [], focus: nil, wordCount: 10, using: &rng) == "")
    }

    @Test("estimatedWPM derives from median latency")
    func estimatedWPM() throws {
        var stat = KeyStat()
        for _ in 0..<50 { stat.latency.add(milliseconds: 120); stat.presses += 1 }
        // ~120ms median reach → roughly 90–100 WPM (the histogram interpolates within its
        // bucket, so the median reads ~130ms, ~92 WPM — the exact figure isn't the point).
        let wpm = try #require(stat.estimatedWPM())
        #expect(wpm > 80 && wpm < 105)
    }
}
