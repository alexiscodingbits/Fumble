import Foundation

/// A generated drill ready to practise: the text to type, and a human-readable list of what it's
/// targeting (shown to the user so the drill doesn't feel arbitrary — "you're practising this
/// *because* these are your slow spots").
public struct DrillPlan: Equatable, Sendable {
    public let text: String
    public let focus: [String]

    public init(text: String, focus: [String]) {
        self.text = text
        self.focus = focus
    }

    public var isWarmUp: Bool { focus.isEmpty }
}
