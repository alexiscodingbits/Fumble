import FumbleCore
import Foundation

/// Tracks one drill in progress: what to type, what's been typed, and how it's going. Pure and
/// timestamp-injected so the whole thing — correctness, accuracy, WPM — is unit-testable without
/// a UI or a clock.
public struct DrillState: Equatable, Sendable {

    public enum CharStatus: Equatable, Sendable {
        case pending    // not reached yet
        case correct
        case incorrect
        case current    // the cursor sits here
    }

    /// What a wrong keystroke does to the cursor.
    public enum ErrorHandling: String, CaseIterable, Sendable {
        /// Monkeytype-style: the wrong character is accepted and the cursor moves on; the user
        /// backspaces to fix it.
        case advance
        /// keybr-style: the cursor stays put until the right character is typed. Retries at the
        /// same position count as keystrokes (attempts) but only the first miss counts as an
        /// error — otherwise a stuck key would let one lapse tank the whole drill's accuracy.
        case stopUntilCorrect
    }

    public let errorHandling: ErrorHandling
    public let target: [Character]
    /// Status per target position, for rendering.
    public private(set) var statuses: [CharStatus]
    /// Index of the next character to type. Equals `target.count` when finished.
    public private(set) var cursor: Int = 0

    /// Every character keystroke, including ones later backspaced — the denominator for accuracy.
    public private(set) var totalTyped: Int = 0
    /// Characters typed wrong on first attempt, even if later corrected — the numerator for errors.
    public private(set) var errors: Int = 0

    /// Whether the most recent counted keystroke was wrong — drives the UI's error flash/sound.
    /// Untouched by ignored input (typing past the end) so a finished drill doesn't flash.
    public private(set) var lastEventWasError: Bool = false

    /// Positions (in `.stopUntilCorrect` mode) that have seen at least one wrong attempt, so
    /// retries aren't double-counted as errors and the eventual correct keystroke can still be
    /// rendered honestly red.
    private var erredPositions: Set<Int> = []

    private var firstKeystroke: Double?
    private var lastKeystroke: Double?

    /// Reach intervals (ms) per key code, for correctly typed characters — feeds the trainer's
    /// confidence update. Only motor-plausible intervals are kept (a long think isn't a reach).
    public private(set) var perKeyIntervals: [Int: [Double]] = [:]
    private let maxReachMilliseconds: Double = 1_500

    public init(target: String, errorHandling: ErrorHandling = .advance) {
        self.target = Array(target)
        self.errorHandling = errorHandling
        self.statuses = Array(repeating: .pending, count: self.target.count)
        if !self.target.isEmpty { statuses[0] = .current }
    }

    public var isComplete: Bool { cursor >= target.count && !target.isEmpty }

    /// Type a character. In `.advance` mode the cursor moves whether right or wrong
    /// (monkeytype-style — you can backspace to fix it, which is exactly the correction
    /// behaviour we want to encourage). In `.stopUntilCorrect` mode a wrong keystroke leaves
    /// the cursor in place and the drill waits for the right character.
    public mutating func type(_ character: Character, at timestamp: Double) {
        guard cursor < target.count else { return }
        let previous = lastKeystroke
        if firstKeystroke == nil { firstKeystroke = timestamp }
        lastKeystroke = timestamp

        totalTyped += 1
        let correct = character == target[cursor]
        lastEventWasError = !correct

        switch errorHandling {
        case .advance:
            if !correct { errors += 1 }
            if correct { recordReach(of: character, at: timestamp, since: previous) }
            statuses[cursor] = correct ? .correct : .incorrect

        case .stopUntilCorrect:
            if !correct {
                // Only the first miss at a position is an error; retries still count as
                // keystrokes (totalTyped) so accuracy reflects the flailing honestly.
                if erredPositions.insert(cursor).inserted { errors += 1 }
                return   // cursor stays; the position remains .current
            }
            let cleanFirstAttempt = !erredPositions.contains(cursor)
            // Timing from an erred position is contaminated by the retry (the interval measures
            // recovery, not the reach), so only clean first attempts feed the trainer.
            if cleanFirstAttempt { recordReach(of: character, at: timestamp, since: previous) }
            // Honest red: the position was eventually typed right, but it did err.
            statuses[cursor] = cleanFirstAttempt ? .correct : .incorrect
        }

        cursor += 1
        if cursor < target.count { statuses[cursor] = .current }
    }

    /// Per-key reach timing for correctly typed characters: interval from the previous
    /// keystroke, kept only when it's a plausible motor reach (not a think-pause).
    ///
    /// The lowercase mapping is done carefully: `Character(String)` traps unless the string
    /// is exactly one grapheme, and a stray keystroke's lowercase form isn't guaranteed to
    /// be, so guard on the grapheme count before constructing the Character.
    private mutating func recordReach(of character: Character, at timestamp: Double, since previous: Double?) {
        guard let previous else { return }
        let milliseconds = (timestamp - previous) * 1000
        let lowered = character.lowercased()
        if milliseconds > 0, milliseconds <= maxReachMilliseconds, lowered.count == 1,
           let keyCode = KeyIdentity.characterToKeyCode[lowered[lowered.startIndex]] {
            perKeyIntervals[keyCode, default: []].append(milliseconds)
        }
    }

    public mutating func backspace() {
        // In stop mode the cursor never advanced past a mistake, so there's nothing to undo.
        guard errorHandling == .advance else { return }
        guard cursor > 0 else { return }
        if cursor < target.count { statuses[cursor] = .pending }
        cursor -= 1
        statuses[cursor] = .current
    }

    /// Accuracy over every keystroke made, 0...1. Nil before anything is typed.
    public var accuracy: Double? {
        guard totalTyped > 0 else { return nil }
        return 1.0 - Double(errors) / Double(totalTyped)
    }

    /// WPM measured over the characters typed so far, across the elapsed drill time. Uses the
    /// standard 5-characters-per-word convention. Nil until there's enough to be meaningful.
    public func wordsPerMinute(now: Double) -> Double? {
        guard let first = firstKeystroke, cursor >= 5 else { return nil }
        let end = isComplete ? (lastKeystroke ?? now) : now
        let minutes = (end - first) / 60
        guard minutes > 0 else { return nil }
        return (Double(cursor) / 5.0) / minutes
    }

    /// Measured WPM per key code from this drill, for feeding the trainer's confidence. Median
    /// reach per key → 12000 / median ms. Only keys with enough samples to be meaningful.
    public func perKeyWPM(minimumSamples: Int = 2) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (keyCode, samples) in perKeyIntervals where samples.count >= minimumSamples {
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            if median > 0 { result[keyCode] = 12_000 / median }
        }
        return result
    }
}
