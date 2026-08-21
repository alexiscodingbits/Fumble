import Foundation
import Testing
@testable import FumbleCore

@Suite("KeyboardTrainer telemetry")
struct KeyboardTrainerTelemetryTests {

    private func code(_ c: Character) -> Int { KeyIdentity.characterToKeyCode[c]! }
    private func key(_ c: Character) -> KeyIdentity { KeyIdentity(keyCode: code(c)) }

    @Test("an unmeasured key reports nil everywhere, not zero")
    func freshKeyIsNil() {
        let trainer = KeyboardTrainer(seed: [code("e"): 30])
        // Even a *seeded* key has no drill history yet — the seed feeds confidence, not telemetry.
        #expect(trainer.lastWPM(for: key("e")) == nil)
        #expect(trainer.topWPM(for: key("e")) == nil)
        #expect(trainer.learningRate(for: key("e")) == nil)
        #expect(trainer.sampleCount(for: key("e")) == 0)
    }

    @Test("last is the most recent raw sample and top is the running max")
    func lastAndTop() {
        let trainer = KeyboardTrainer(seed: [:])
        trainer.record(perKeyWPM: [code("e"): 30])
        trainer.record(perKeyWPM: [code("e"): 54.1])
        trainer.record(perKeyWPM: [code("e"): 36.3])
        #expect(trainer.lastWPM(for: key("e")) == 36.3)   // raw, not the blended `wpm` value
        #expect(trainer.topWPM(for: key("e")) == 54.1)    // max survives a slower follow-up
        #expect(trainer.sampleCount(for: key("e")) == 3)
    }

    @Test("learning rate is the least-squares slope: 10,12,14 is exactly +2 per lesson")
    func learningRateSlope() {
        let trainer = KeyboardTrainer(seed: [:])
        for sample in [10.0, 12.0, 14.0] {
            trainer.record(perKeyWPM: [code("e"): sample])
        }
        // Perfectly linear samples: the slope is exact, no tolerance needed.
        #expect(trainer.learningRate(for: key("e")) == 2.0)
    }

    @Test("a declining key reads as a negative rate")
    func learningRateNegative() {
        let trainer = KeyboardTrainer(seed: [:])
        for sample in [40.0, 37.0, 34.0, 31.0] {
            trainer.record(perKeyWPM: [code("t"): sample])
        }
        #expect(trainer.learningRate(for: key("t")) == -3.0)
    }

    @Test("learning rate is nil under 3 samples — two points aren't a trend")
    func learningRateNeedsThree() {
        let trainer = KeyboardTrainer(seed: [:])
        trainer.record(perKeyWPM: [code("e"): 20])
        #expect(trainer.learningRate(for: key("e")) == nil)
        trainer.record(perKeyWPM: [code("e"): 25])
        #expect(trainer.learningRate(for: key("e")) == nil)
        trainer.record(perKeyWPM: [code("e"): 30])
        #expect(trainer.learningRate(for: key("e")) != nil)
    }

    @Test("history caps at 20 samples, dropping the oldest, but top persists past the cap")
    func capDropsOldestTopSurvives() {
        let trainer = KeyboardTrainer(seed: [:])
        trainer.record(perKeyWPM: [code("e"): 99])           // the all-time best, recorded first
        for i in 0..<25 {
            trainer.record(perKeyWPM: [code("e"): 20.0 + Double(i)])
        }
        #expect(trainer.sampleCount(for: key("e")) == 20)    // capped, not 26
        #expect(trainer.lastWPM(for: key("e")) == 44)        // newest kept: 20 + 24
        #expect(trainer.topWPM(for: key("e")) == 99)         // the evicted peak is still the top
        // The 99 left the window, so the trend reflects only the steady +1 climb.
        #expect(trainer.learningRate(for: key("e")) == 1.0)
    }

    @Test("non-positive samples are 'not measured' and never enter history")
    func zeroSamplesIgnored() {
        let trainer = KeyboardTrainer(seed: [:])
        trainer.record(perKeyWPM: [code("e"): 30, code("t"): 0])
        #expect(trainer.lastWPM(for: key("e")) == 30)
        #expect(trainer.lastWPM(for: key("t")) == nil)
        #expect(trainer.sampleCount(for: key("t")) == 0)
    }

    @Test("telemetry rides along without changing the blended confidence update")
    func confidenceUpdateUnchanged() {
        var config = KeyboardTrainer.Config()
        config.blend = 0.3
        let trainer = KeyboardTrainer(seed: [code("e"): 20], config: config)
        trainer.record(perKeyWPM: [code("e"): 40])
        // The unlock signal still blends (20 + (40-20)*0.3 = 26) while history keeps the raw 40.
        #expect(abs(trainer.wpm[code("e")]! - 26) < 0.001)
        #expect(trainer.lastWPM(for: key("e")) == 40)
    }

    @Test("recording telemetry still drives unlocks exactly as before")
    func unlocksUnchanged() {
        let trainer = KeyboardTrainer(seed: [:])
        let before = trainer.unlockedCount
        let mastered = Dictionary(uniqueKeysWithValues: trainer.unlockedKeys.map { ($0.keyCode, 80.0) })
        trainer.record(perKeyWPM: mastered)
        #expect(trainer.unlockedCount == before + 1)
        // And every reported key picked up its raw sample on the way through.
        for k in Array(trainer.unlockedKeys.prefix(before)) {
            #expect(trainer.lastWPM(for: k) == 80)
        }
    }
}
