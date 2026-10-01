/// Line-wraps drill text ourselves, in whole monospaced columns, so the caret's position is
/// arithmetic (column × glyph width, line × line height) rather than something read back from
/// the text engine — SwiftUI `Text` exposes no glyph geometry on macOS 14. That is what lets a
/// monkeytype-style bar caret sit exactly between characters and slide as you type.
public enum TypingLayout {

    public struct Position: Equatable, Sendable {
        public let line: Int
        public let column: Int
        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    /// Greedy word wrap into index ranges. A space stays at the end of the line it ends (so it may
    /// sit one column past `columns` — callers leave that column spare); a word longer than a
    /// whole line is hard-broken.
    public static func wrap(_ target: [Character], columns: Int) -> [Range<Int>] {
        let columns = max(columns, 1)
        var lines: [Range<Int>] = []
        var lineStart = 0
        var index = 0
        while index < target.count {
            // One word plus its trailing spaces.
            var wordEnd = index
            while wordEnd < target.count, target[wordEnd] != " " { wordEnd += 1 }
            var chunkEnd = wordEnd
            while chunkEnd < target.count, target[chunkEnd] == " " { chunkEnd += 1 }

            if wordEnd - lineStart > columns, index > lineStart {
                lines.append(lineStart..<index)
                lineStart = index
            }
            while wordEnd - lineStart > columns {
                lines.append(lineStart..<(lineStart + columns))
                lineStart += columns
            }
            index = chunkEnd
        }
        if lineStart < target.count { lines.append(lineStart..<target.count) }
        return lines
    }

    /// Where the caret goes: just before the character at `cursor`, or after the last character
    /// once the drill is complete.
    public static func caret(cursor: Int, in lines: [Range<Int>]) -> Position {
        guard let last = lines.last else { return Position(line: 0, column: 0) }
        if let line = lines.firstIndex(where: { $0.contains(cursor) }) {
            return Position(line: line, column: cursor - lines[line].lowerBound)
        }
        return Position(line: lines.count - 1, column: last.count)
    }
}
