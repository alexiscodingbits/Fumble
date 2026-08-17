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

    public let target: [Character]
    /// Status per target position, for rendering.
    public private(set) var statuses: [CharStatus]
    /// Index of the next character to type. Equals `target.count` when finished.
    public private(set) var cursor: Int = 0

    /// Every character keystroke, including ones later backspaced — the denominator for accuracy.
    public private(set) var totalTyped: Int = 0
    /// Characters typed wrong on first attempt, even if later corrected — the numerator for errors.
    public private(set) var errors: Int = 0

    private var firstKeystroke: Double?
    private var lastKeystroke: Double?

    public init(target: String) {
        self.target = Array(target)
        self.statuses = Array(repeating: .pending, count: self.target.count)
        if !self.target.isEmpty { statuses[0] = .current }
    }

    public var isComplete: Bool { cursor >= target.count && !target.isEmpty }

    /// Type a character. Advances the cursor whether right or wrong (monkeytype-style — you can
    /// backspace to fix it, which is exactly the correction behaviour we want to encourage).
    public mutating func type(_ character: Character, at timestamp: Double) {
        guard cursor < target.count else { return }
        if firstKeystroke == nil { firstKeystroke = timestamp }
        lastKeystroke = timestamp

        totalTyped += 1
        let correct = character == target[cursor]
        if !correct { errors += 1 }
        statuses[cursor] = correct ? .correct : .incorrect
        cursor += 1
        if cursor < target.count { statuses[cursor] = .current }
    }

    public mutating func backspace() {
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
}
