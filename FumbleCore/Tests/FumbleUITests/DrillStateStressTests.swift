import Foundation
import Testing
@testable import FumbleCore
@testable import FumbleUI

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

@Suite("DrillState stress")
struct DrillStateStressTests {

    @Test("random typing (including weird characters and backspace spam) never crashes or corrupts")
    func fuzz() {
        var rng = SeededRNG(seed: 1)
        // A mix of normal, uppercase, punctuation, emoji, and multi-scalar characters — exactly
        // the kind of thing that trapped the per-key lowercase mapping before it was guarded.
        let pool: [Character] = ["a", "b", "Z", " ", ".", "é", "İ", "😀", "ß", "1"]

        for seed in 0..<50 {
            rng = SeededRNG(seed: UInt64(seed))
            var drill = DrillState(target: "the quick brown fox")
            var clock = 0.0
            for _ in 0..<200 {
                clock += Double.random(in: 0...0.3, using: &rng)
                if Bool.random(using: &rng), Double.random(in: 0...1, using: &rng) < 0.25 {
                    drill.backspace()
                } else {
                    drill.type(pool.randomElement(using: &rng)!, at: clock)
                }
                // Invariants after every action.
                #expect(drill.cursor >= 0 && drill.cursor <= drill.target.count)
                #expect(drill.errors <= drill.totalTyped)
            }
            // Derived values must be finite when present.
            if let acc = drill.accuracy { #expect(acc >= 0 && acc <= 1) }
            if let wpm = drill.wordsPerMinute(now: clock + 1) { #expect(wpm.isFinite && wpm >= 0) }
            for (_, wpm) in drill.perKeyWPM() { #expect(wpm.isFinite && wpm > 0) }
        }
    }

    @Test("empty target is inert")
    func emptyTarget() {
        var drill = DrillState(target: "")
        drill.type("a", at: 0)
        drill.backspace()
        #expect(!drill.isComplete)
        #expect(drill.perKeyWPM().isEmpty)
    }

    @Test("typing far past the end is ignored")
    func overrun() {
        var drill = DrillState(target: "hi")
        for i in 0..<100 { drill.type("x", at: Double(i) * 0.1) }
        #expect(drill.totalTyped == 2)
        #expect(drill.isComplete)
    }

    @Test("LiveSpeed survives bursts, idle, and reset")
    func liveSpeed() {
        var live = LiveSpeed()
        for i in 0..<1000 { live.record(timestamp: Double(i) * 0.01) }
        #expect(live.wordsPerMinute(now: 10.0) != nil)
        live.reset()
        #expect(live.wordsPerMinute(now: 10.0) == nil)
        // A single far-future sample → idle, no crash.
        live.record(timestamp: 100_000)
        #expect(live.wordsPerMinute(now: 100_010) == nil)
    }
}
