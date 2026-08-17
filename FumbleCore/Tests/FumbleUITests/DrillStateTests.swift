import Foundation
import Testing
@testable import FumbleUI

@Suite("DrillState")
struct DrillStateTests {

    @Test("starts with the cursor on the first character")
    func initialState() {
        let state = DrillState(target: "cat")
        #expect(state.cursor == 0)
        #expect(state.statuses.first == .current)
        #expect(!state.isComplete)
        #expect(state.accuracy == nil)
    }

    @Test("correct typing advances and marks correct")
    func correctTyping() {
        var state = DrillState(target: "cat")
        state.type("c", at: 0)
        #expect(state.statuses[0] == .correct)
        #expect(state.statuses[1] == .current)
        #expect(state.cursor == 1)
    }

    @Test("a wrong character is marked incorrect but still advances")
    func wrongCharacter() {
        var state = DrillState(target: "cat")
        state.type("x", at: 0)
        #expect(state.statuses[0] == .incorrect)
        #expect(state.cursor == 1)
        #expect(state.errors == 1)
        #expect(state.totalTyped == 1)
    }

    @Test("backspace steps back and clears the status")
    func backspace() {
        var state = DrillState(target: "cat")
        state.type("x", at: 0)
        state.backspace()
        #expect(state.cursor == 0)
        #expect(state.statuses[0] == .current)
        // The error is still counted — you did mistype, even though you fixed it.
        #expect(state.errors == 1)
        #expect(state.totalTyped == 1)
    }

    @Test("backspace at the start does nothing")
    func backspaceAtStart() {
        var state = DrillState(target: "cat")
        state.backspace()
        #expect(state.cursor == 0)
    }

    @Test("completes when the last character is typed")
    func completion() {
        var state = DrillState(target: "hi")
        state.type("h", at: 0)
        #expect(!state.isComplete)
        state.type("i", at: 0.1)
        #expect(state.isComplete)
        // Typing past the end is ignored.
        state.type("x", at: 0.2)
        #expect(state.totalTyped == 2)
    }

    @Test("accuracy reflects mistakes made")
    func accuracy() throws {
        var state = DrillState(target: "abcd")
        state.type("a", at: 0)
        state.type("x", at: 0.1)   // wrong
        state.type("c", at: 0.2)
        state.type("d", at: 0.3)
        let accuracy = try #require(state.accuracy)
        #expect(abs(accuracy - 0.75) < 0.001)   // 3 of 4 correct
    }

    @Test("WPM is measured over elapsed typing time")
    func wpm() throws {
        // 10 characters typed at 100ms each = 0.9s from first to last.
        var state = DrillState(target: "abcdefghij")
        for (i, ch) in "abcdefghij".enumerated() {
            state.type(ch, at: Double(i) * 0.1)
        }
        #expect(state.isComplete)
        let wpm = try #require(state.wordsPerMinute(now: 0.9))
        // 10 chars / 5 over 0.9s ≈ 133 WPM.
        #expect(wpm > 120 && wpm < 150)
    }

    @Test("no WPM before five characters")
    func wpmNeedsSamples() {
        var state = DrillState(target: "abcdefghij")
        state.type("a", at: 0)
        state.type("b", at: 0.1)
        #expect(state.wordsPerMinute(now: 0.1) == nil)
    }

    @Test("empty target is trivially not in progress")
    func emptyTarget() {
        let state = DrillState(target: "")
        #expect(!state.isComplete)   // nothing to type; never 'completes'
        #expect(state.statuses.isEmpty)
    }
}
