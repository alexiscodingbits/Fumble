import FumbleUI
import SwiftUI

/// How the "type this next" position is drawn. Mirrors keybr's cursor-shape option.
enum CursorStyle: String, CaseIterable, Identifiable {
    case block, underline, line
    var id: String { rawValue }
    var title: String {
        switch self {
        case .block: "Block"
        case .underline: "Underline"
        case .line: "Line"
        }
    }
}

/// Renders a drill target as an AttributedString: one place for the colour scheme, whitespace
/// dots, and cursor style, shared by every practice surface (trainer, drills, future modes).
enum TypingText {

    /// - Parameter showWhitespaceDots: draw spaces as `·` (keybr's "bullet whitespace").
    ///   Colour still tracks status, so a mistyped space stays visibly red.
    static func render(
        target: [Character],
        statuses: [DrillState.CharStatus],
        showWhitespaceDots: Bool,
        cursorStyle: CursorStyle
    ) -> AttributedString {
        var result = AttributedString()
        for (index, character) in target.enumerated() {
            let display: String = (character == " " && showWhitespaceDots) ? "·" : String(character)
            var piece = AttributedString(display)
            switch statuses[index] {
            case .pending:
                piece.foregroundColor = .secondary.opacity(character == " " && showWhitespaceDots ? 0.35 : 0.5)
            case .correct:
                piece.foregroundColor = character == " " && showWhitespaceDots
                    ? .secondary.opacity(0.6)   // typed dots recede so words stay readable
                    : .primary
            case .incorrect:
                piece.foregroundColor = .red
                if character == " " { piece.underlineStyle = .single }
            case .current:
                piece.foregroundColor = .primary
                switch cursorStyle {
                case .block:
                    piece.backgroundColor = .accentColor.opacity(0.35)
                case .underline:
                    piece.underlineStyle = .single
                    piece.underlineColor = NSColor.controlAccentColor
                case .line:
                    // A thin marker before the character: approximate with a leading bar glyph
                    // is ugly; instead tint the character itself so position stays obvious.
                    piece.foregroundColor = Color.accentColor
                    piece.underlineStyle = .single
                    piece.underlineColor = NSColor.controlAccentColor.withAlphaComponent(0.4)
                }
            }
            result += piece
        }
        return result
    }
}
