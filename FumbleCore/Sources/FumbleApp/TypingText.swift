import AppKit
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

/// The drill text, shared by every practice surface (trainer, drills, future modes).
///
/// Wraps itself in whole monospaced columns (`TypingLayout`) so the `.line` caret can be a real
/// monkeytype bar: it sits *between* characters, slides as you type, and the character after it
/// stays grey until it's actually pressed.
struct TypingTextView: View {
    let target: [Character]
    let statuses: [DrillState.CharStatus]
    let cursor: Int
    let showWhitespaceDots: Bool
    let cursorStyle: CursorStyle

    @State private var width: CGFloat = 0

    private static let lineGap: CGFloat = 8
    private static let nsFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
    private static let charWidth = ("M" as NSString).size(withAttributes: [.font: nsFont]).width
    private static let lineHeight = ceil(nsFont.ascender - nsFont.descender + nsFont.leading)

    var body: some View {
        // One column spare: a line-ending space may overhang by one (see `TypingLayout.wrap`).
        let columns = width > 0 ? max(Int(width / Self.charWidth) - 1, 8) : 60
        let lines = TypingLayout.wrap(target, columns: columns)
        VStack(alignment: .leading, spacing: Self.lineGap) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, range in
                Text(TypingText.render(target: target, statuses: statuses, range: range,
                                       showWhitespaceDots: showWhitespaceDots, cursorStyle: cursorStyle))
                    .font(Font(Self.nsFont as CTFont))
                    .fixedSize()
                    .frame(height: Self.lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.lineHeight, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if cursorStyle == .line { caret(at: TypingLayout.caret(cursor: cursor, in: lines)) }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, new in width = new }
        })
    }

    private func caret(at position: TypingLayout.Position) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Theme.fumbleOrange)
            .frame(width: 2.5, height: Self.lineHeight * 0.85)
            .offset(x: CGFloat(position.column) * Self.charWidth - 1.25,
                    y: CGFloat(position.line) * (Self.lineHeight + Self.lineGap) + Self.lineHeight * 0.075)
            .animation(.easeOut(duration: 0.09), value: position)
    }
}

/// Renders one line of a drill target as an AttributedString: the colour scheme, whitespace
/// dots, and the block/underline cursor styles.
enum TypingText {

    /// - Parameter showWhitespaceDots: draw spaces as `·` (keybr's "bullet whitespace").
    ///   Colour still tracks status, so a mistyped space stays visibly red.
    static func render(
        target: [Character],
        statuses: [DrillState.CharStatus],
        range: Range<Int>,
        showWhitespaceDots: Bool,
        cursorStyle: CursorStyle
    ) -> AttributedString {
        var result = AttributedString()
        for index in range {
            let character = target[index]
            let dotted = character == " " && showWhitespaceDots
            var piece = AttributedString(dotted ? "·" : String(character))
            switch statuses[index] {
            case .pending:
                piece.foregroundColor = Theme.untypedText.opacity(dotted ? 0.6 : 1)
            case .correct:
                piece.foregroundColor = dotted
                    ? Theme.untypedText.opacity(0.8)   // typed dots recede so words stay readable
                    : .primary
            case .incorrect:
                piece.foregroundColor = .red
                if character == " " { piece.underlineStyle = .single }
            case .current:
                switch cursorStyle {
                case .block:
                    piece.foregroundColor = .primary
                    piece.backgroundColor = Theme.fumbleOrange.opacity(0.35)
                case .underline:
                    piece.foregroundColor = .primary
                    piece.underlineStyle = .single
                    piece.underlineColor = NSColor(Theme.fumbleOrange)
                case .line:
                    // The bar caret is drawn by `TypingTextView`; the character stays untyped-grey
                    // until it's pressed, as in monkeytype.
                    piece.foregroundColor = Theme.untypedText.opacity(dotted ? 0.6 : 1)
                }
            }
            result += piece
        }
        return result
    }
}
