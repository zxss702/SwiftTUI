import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
struct TextLineBreakTests {

    private func lineStrings(_ text: String, width: Int) -> [String] {
        TextLayout.wrap(text, width: width)
    }

    @Test func englishBreaksAtWordBoundary() {
        let lines = lineStrings("hello world", width: 8)
        #expect(lines.count == 2)
        #expect(lines[0] == "hello ")
        #expect(lines[1] == "world")
    }

    @Test func englishDoesNotSplitWord() {
        let lines = lineStrings("hello world", width: 5)
        #expect(lines.count == 2)
        #expect(lines[0] == "hello")
        #expect(lines[1] == "world")
    }

    @Test func longEnglishWordForceBreaks() {
        let lines = lineStrings("abcdefghij", width: 4)
        #expect(lines.count >= 2)
        #expect(lines[0] == "abcd")
        #expect(lines.joined() == "abcdefghij")
    }

    @Test func cjkAvoidsLeadingPunctuation() {
        let text = "你好，世界！"
        let lines = TextLayout.lines(for: text, width: 8, lineLimit: nil, truncationMode: .tail)
        for line in lines.dropFirst() {
            if let first = line.string.first {
                #expect(!LineBreakEngine.isLineStartProhibited(first))
            }
        }
    }

    @Test func cjkOpeningBracketNotAloneAtLineEnd() {
        let text = "「你好世界」"
        let lines = TextLayout.lines(for: text, width: 6, lineLimit: nil, truncationMode: .tail)
        for line in lines where !line.string.isEmpty {
            if let last = line.string.last {
                #expect(!LineBreakEngine.isLineEndProhibited(last))
            }
        }
    }

    @Test func mixedScriptBreaks() {
        let lines = lineStrings("Hello你好World", width: 10)
        #expect(lines.count >= 1)
        #expect(lines.joined() == "Hello你好World")
    }

    @Test func wrapKeepsSourceIndicesAcrossSoftWrap() {
        let text = "abcdef"
        let lines = TextLayout.lines(
            for: text,
            width: 3,
            lineLimit: nil,
            truncationMode: .tail
        )
        #expect(lines.count == 2)
        #expect(lines[0].units.map(\.char) == Array("abc"))
        #expect(lines[0].units.map(\.sourceIndex) == [0, 1, 2])
        #expect(lines[1].units.map(\.char) == Array("def"))
        #expect(lines[1].units.map(\.sourceIndex) == [3, 4, 5])
    }

    @Test func truncateTailMarksEllipsisWithoutSourceIndex() {
        let text = "abcdefghij"
        let lines = TextLayout.lines(
            for: text,
            width: 4,
            lineLimit: 1,
            truncationMode: .tail
        )
        #expect(lines.count == 1)
        let units = lines[0].units
        #expect(units.last?.char == "…")
        #expect(units.last?.sourceIndex == nil)
        #expect(units.dropLast().allSatisfy { $0.sourceIndex != nil })
    }

    @Test func explicitNewlineCreatesLineBreak() {
        let lines = lineStrings("ab\ncd", width: 10)
        #expect(lines.count == 2)
        #expect(lines[0] == "ab")
        #expect(lines[1] == "cd")
    }
}