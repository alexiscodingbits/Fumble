import Testing
@testable import FumbleUI

@Suite("TypingLayout")
struct TypingLayoutTests {

    private func lines(_ text: String, _ columns: Int) -> [String] {
        let target = Array(text)
        return TypingLayout.wrap(target, columns: columns).map { String(target[$0]) }
    }

    @Test("short text stays on one line")
    func singleLine() {
        #expect(lines("the cat", 20) == ["the cat"])
    }

    @Test("breaks between words, the space stays at the end of the line it ends")
    func breaksAtSpaces() {
        #expect(lines("the cat sat", 7) == ["the cat ", "sat"])
    }

    @Test("a word is never split when it fits on a line of its own")
    func wordsStayWhole() {
        #expect(lines("ab abcdef", 6) == ["ab ", "abcdef"])
    }

    @Test("a word longer than a line is hard-broken")
    func hardBreak() {
        #expect(lines("abcdefgh", 3) == ["abc", "def", "gh"])
    }

    @Test("the line ranges cover every character exactly once")
    func coversEverything() {
        let target = Array("lorem ipsum dolor sit amet consectetur")
        let ranges = TypingLayout.wrap(target, columns: 9)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == target.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
    }

    @Test("caret sits before the character at the cursor, wrapping to the next line's start")
    func caretPosition() {
        let ranges = TypingLayout.wrap(Array("the cat sat"), columns: 7)   // "the cat " / "sat"
        #expect(TypingLayout.caret(cursor: 0, in: ranges) == .init(line: 0, column: 0))
        #expect(TypingLayout.caret(cursor: 4, in: ranges) == .init(line: 0, column: 4))
        #expect(TypingLayout.caret(cursor: 8, in: ranges) == .init(line: 1, column: 0))
    }

    @Test("caret after the last character sits at the end of the last line")
    func caretAtEnd() {
        let ranges = TypingLayout.wrap(Array("the cat sat"), columns: 7)
        #expect(TypingLayout.caret(cursor: 11, in: ranges) == .init(line: 1, column: 3))
        #expect(TypingLayout.caret(cursor: 0, in: []) == .init(line: 0, column: 0))
    }
}
