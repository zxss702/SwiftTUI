import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct AttributedTextTests {

    @Test func flattenPreservesPerCharacterStyles() throws {
        var attributed = AttributedString("ab")
        let firstEnd = attributed.index(attributed.startIndex, offsetByCharacters: 1)
        attributed[attributed.startIndex ..< firstEnd].swiftTUI.foregroundColor = .red
        attributed[attributed.startIndex ..< firstEnd].swiftTUI.bold = true
        attributed[firstEnd ..< attributed.endIndex].swiftTUI.foregroundColor = .green
        attributed[firstEnd ..< attributed.endIndex].swiftTUI.italic = true

        let flattened = AttributedTextStyle.flatten(attributed)
        #expect(flattened.string == "ab")
        let styles = try #require(flattened.styles)
        #expect(styles.count == 2)
        #expect(styles[0].foreground == .red)
        #expect(styles[0].bold == true)
        #expect(styles[1].foreground == .green)
        #expect(styles[1].italic == true)
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

    @Test func drawAppliesRunForegroundAndBold() async throws {
        var attributed = AttributedString("XY")
        let firstEnd = attributed.index(attributed.startIndex, offsetByCharacters: 1)
        attributed[attributed.startIndex ..< firstEnd].swiftTUI.foregroundColor = .red
        attributed[attributed.startIndex ..< firstEnd].swiftTUI.bold = true
        attributed[firstEnd ..< attributed.endIndex].swiftTUI.foregroundColor = .cyan

        let app = Application(rootView: Text(attributed))
        try await app.testing_prepare(size: Size(width: 8, height: 3))
        let textEl = try #require(findTextElement(in: app.testing_rootElement, equalTo: "XY"))

        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: textEl.layer.frame.size)
        )
        textEl.draw(into: &buffer)

        let cell0 = try #require(buffer.cell(at: Position(column: 0, line: 0)))
        let cell1 = try #require(buffer.cell(at: Position(column: 1, line: 0)))
        #expect(cell0.char == "X")
        #expect(cell0.foregroundColor == .red)
        #expect(cell0.attributes.bold == true)
        #expect(cell1.char == "Y")
        #expect(cell1.foregroundColor == .cyan)
        #expect(cell1.attributes.bold == false)
    }
}

@MainActor
private func findTextElement(in control: Element?, equalTo target: String) -> Element? {
    guard let control else { return nil }
    if textLabel(in: control) == target { return control }
    for child in control.children {
        if let found = findTextElement(in: child, equalTo: target) { return found }
    }
    return nil
}

@MainActor
private func textLabel(in control: Element) -> String? {
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
        return text
    }
    for child in control.children {
        if let text = textLabel(in: child) { return text }
    }
    return nil
}
