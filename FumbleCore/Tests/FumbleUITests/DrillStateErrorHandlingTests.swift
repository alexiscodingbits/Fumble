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

@Suite("DrillState error handling")
struct DrillStateErrorHandlingTests {

    // MARK: - .stopUntilCorrect semantics

    @Test("a wrong character does not advance the cursor")
    func wrongCharacterStops() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        state.type("x", at: 0)
        #expect(state.cursor == 0)
        #expect(state.statuses[0] == .current)
        #expect(state.statuses[1] == .pending)
        #expect(state.totalTyped == 1)
        #expect(state.errors == 1)
    }

    @Test("every retry at a stuck position counts as an error, like keybr")
    func retriesAllCount() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        state.type("x", at: 0)
        state.type("y", at: 0.1)
        state.type("z", at: 0.2)
        #expect(state.cursor == 0)
        #expect(state.totalTyped == 3)
        // Both counters move per attempt — errors/totalTyped is only an honest accuracy when
        // they do. (Counting only the first miss made accuracy RISE with flailing.)
        #expect(state.errors == 3)
    }

    @Test("correcting an erred position advances but stays honestly red")
    func honestRedAfterCorrection() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        state.type("x", at: 0)
        state.type("c", at: 0.1)
        #expect(state.cursor == 1)
        #expect(state.statuses[0] == .incorrect)   // it did err, even though it's now right
        #expect(state.statuses[1] == .current)
        // A clean first attempt stays green.
        state.type("a", at: 0.2)
        #expect(state.statuses[1] == .correct)
    }

    @Test("errors accumulate across positions and retries")
    func errorsAccumulate() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        state.type("x", at: 0)     // err at 0
        state.type("c", at: 0.1)
        state.type("a", at: 0.2)   // clean
        state.type("x", at: 0.3)   // err at 2
        state.type("x", at: 0.4)   // retry at 2 — also an error
        state.type("t", at: 0.5)
        #expect(state.errors == 3)
        #expect(state.totalTyped == 6)
        #expect(state.isComplete)
    }

    @Test("completes despite errors, and input past the end stays ignored")
    func completion() {
        var state = DrillState(target: "hi", errorHandling: .stopUntilCorrect)
        state.type("x", at: 0)
        state.type("h", at: 0.1)
        state.type("i", at: 0.2)
        #expect(state.isComplete)
        state.type("q", at: 0.3)
        #expect(state.totalTyped == 3)
    }

    @Test("accuracy degrades monotonically with flailing")
    func accuracy() throws {
        var state = DrillState(target: "abc", errorHandling: .stopUntilCorrect)
        state.type("a", at: 0)
        state.type("x", at: 0.1)   // wrong
        state.type("x", at: 0.2)   // wrong again — another error
        state.type("b", at: 0.3)
        state.type("c", at: 0.4)
        #expect(state.totalTyped == 5)
        #expect(state.errors == 2)
        let accuracy = try #require(state.accuracy)
        #expect(abs(accuracy - 0.6) < 0.001)   // 2 errors over 5 attempts

        // The regression this guards: more flailing must never REPORT better accuracy. One
        // clean run vs the same run plus an extra miss:
        var clean = DrillState(target: "abc", errorHandling: .stopUntilCorrect)
        for (i, ch) in "abc".enumerated() { clean.type(ch, at: Double(i) * 0.1) }
        #expect(try #require(clean.accuracy) > accuracy)
    }

    @Test("intervals are recorded only for positions correct on the first attempt")
    func firstAttemptIntervalsOnly() throws {
        let aKey = try #require(KeyIdentity.characterToKeyCode["a"])
        let bKey = try #require(KeyIdentity.characterToKeyCode["b"])
        var state = DrillState(target: "cab", errorHandling: .stopUntilCorrect)
        state.type("c", at: 0)     // clean, but no previous keystroke → no interval
        state.type("x", at: 0.1)   // err at position 1
        state.type("a", at: 0.2)   // corrected — timing contaminated by the retry
        state.type("b", at: 0.3)   // clean first attempt → 100ms from the previous keystroke
        #expect(state.perKeyIntervals[aKey] == nil)
        let bIntervals = try #require(state.perKeyIntervals[bKey])
        #expect(bIntervals.count == 1)
        #expect(abs(bIntervals[0] - 100) < 0.001)
    }

    @Test("backspace is a no-op — nothing ever advanced past a mistake")
    func backspaceNoOp() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        state.type("c", at: 0)
        state.type("x", at: 0.1)
        let before = state
        state.backspace()
        #expect(state == before)
        // Typing still works normally afterwards.
        state.type("a", at: 0.2)
        #expect(state.cursor == 2)
    }

    // MARK: - lastEventWasError

    @Test("stop mode: error flag follows wrong and correct keystrokes")
    func lastEventWasErrorStopMode() {
        var state = DrillState(target: "cat", errorHandling: .stopUntilCorrect)
        #expect(!state.lastEventWasError)
        state.type("x", at: 0)
        #expect(state.lastEventWasError)
        state.type("y", at: 0.1)     // still stuck, still an error
        #expect(state.lastEventWasError)
        state.type("c", at: 0.2)
        #expect(!state.lastEventWasError)
    }

    @Test("advance mode: error flag follows keystrokes and ignores input past the end")
    func lastEventWasErrorAdvanceMode() {
        var state = DrillState(target: "hi", errorHandling: .advance)
        state.type("h", at: 0)
        #expect(!state.lastEventWasError)
        state.type("x", at: 0.1)   // wrong final character — drill completes in advance mode
        #expect(state.lastEventWasError)
        #expect(state.isComplete)
        // Ignored input must not touch the flag, even when it would be "correct".
        state.type("i", at: 0.2)
        #expect(state.lastEventWasError)
    }

    // MARK: - .advance is the old behaviour

    @Test("advance mode keeps the old semantics: advance on error, per-keystroke errors, backspace")
    func advanceModeOldSemantics() throws {
        var state = DrillState(target: "cat", errorHandling: .advance)
        state.type("x", at: 0)             // wrong: still advances, marked incorrect
        #expect(state.cursor == 1)
        #expect(state.statuses[0] == .incorrect)
        state.backspace()                  // backspace still works
        #expect(state.cursor == 0)
        #expect(state.statuses[0] == .current)
        state.type("x", at: 0.1)           // wrong again: counted again (no first-attempt cap)
        #expect(state.errors == 2)
        state.backspace()
        state.type("c", at: 0.2)           // correct after an err: interval still recorded
        #expect(state.statuses[0] == .correct)   // no honest-red in advance mode
        let cKey = try #require(KeyIdentity.characterToKeyCode["c"])
        #expect(state.perKeyIntervals[cKey]?.count == 1)
    }

    @Test("the default init is exactly .advance, keystroke for keystroke")
    func defaultInitIsAdvance() {
        let pool: [Character] = ["t", "h", "e", " ", "x", "Z", "é", "😀"]
        for seed in 0..<20 {
            var rng = SeededRNG(seed: UInt64(seed))
            var implicit = DrillState(target: "the cat")
            var explicit = DrillState(target: "the cat", errorHandling: .advance)
            var clock = 0.0
            for _ in 0..<80 {
                clock += Double.random(in: 0...0.3, using: &rng)
                if Double.random(in: 0...1, using: &rng) < 0.25 {
                    implicit.backspace()
                    explicit.backspace()
                } else {
                    let ch = pool.randomElement(using: &rng)!
                    implicit.type(ch, at: clock)
                    explicit.type(ch, at: clock)
                }
                // Equatable covers every stored property — statuses, counters, intervals, flag.
                #expect(implicit == explicit)
            }
        }
    }

    @Test("random stop-mode input never corrupts the state")
    func stopModeFuzz() {
        let pool: [Character] = ["t", "h", "e", " ", "q", "Z", "é", "İ", "😀", "1"]
        for seed in 0..<50 {
            var rng = SeededRNG(seed: UInt64(seed))
            var drill = DrillState(target: "the quick", errorHandling: .stopUntilCorrect)
            var clock = 0.0
            for _ in 0..<200 {
                clock += Double.random(in: 0...0.3, using: &rng)
                if Double.random(in: 0...1, using: &rng) < 0.2 {
                    drill.backspace()
                } else {
                    drill.type(pool.randomElement(using: &rng)!, at: clock)
                }
                #expect(drill.cursor >= 0 && drill.cursor <= drill.target.count)
                // Every miss counts (keybr semantics), so errors are bounded by attempts.
                #expect(drill.errors <= drill.totalTyped)
                if !drill.isComplete, !drill.target.isEmpty {
                    #expect(drill.statuses[drill.cursor] == .current)
                }
            }
            if let acc = drill.accuracy { #expect(acc >= 0 && acc <= 1) }
            if let wpm = drill.wordsPerMinute(now: clock + 1) { #expect(wpm.isFinite && wpm >= 0) }
        }
    }
}
