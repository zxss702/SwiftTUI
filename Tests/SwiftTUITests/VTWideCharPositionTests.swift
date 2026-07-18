import Foundation
import Testing
@testable import SwiftTUI

/// VT / ScreenBuffer 宽字符：无孤儿 continuation、TextEdit 不越界、width==0 不卡光标。
@Suite(.serialized)
@MainActor
struct VTWideCharPositionTests {
    @Test func screenBufferWideToNarrowClearsContinuation() {
        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: Size(width: 4, height: 1))
        )
        buffer.setCell(Cell(char: "中"), at: Position(column: 0, line: 0))
        #expect(buffer.character(at: Position(column: 0, line: 0)) == Character("中"))
        #expect(buffer.character(at: Position(column: 1, line: 0)) == Character("\u{0000}"))

        buffer.setCell(Cell(char: "a"), at: Position(column: 0, line: 0))
        #expect(buffer.character(at: Position(column: 0, line: 0)) == Character("a"))
        #expect(
            buffer.character(at: Position(column: 1, line: 0)) == Character(" "),
            "narrow overwrite must clear orphan continuation"
        )
    }

    @Test func screenBufferWriteOnContinuationRetreatsToLead() {
        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: Size(width: 4, height: 1))
        )
        buffer.setCell(Cell(char: "中"), at: Position(column: 0, line: 0))
        // Write onto the continuation column — should replace the whole grapheme.
        buffer.setCell(Cell(char: "b"), at: Position(column: 1, line: 0))
        #expect(buffer.character(at: Position(column: 0, line: 0)) == Character("b"))
        #expect(buffer.character(at: Position(column: 1, line: 0)) == Character(" "))
    }

    @Test func vtBufferSkipsZeroWidthWithoutStallingCursor() {
        var buf = VTBuffer(size: Size(width: 8, height: 2))
        let zw = Character("\u{200B}") // ZERO WIDTH SPACE
        #expect(zw.width == 0)

        buf.write(string: "a\(zw)b", at: VTPosition(row: 1, column: 1))
        #expect(buf[VTPosition(row: 1, column: 1)].character == "a")
        #expect(buf[VTPosition(row: 1, column: 2)].character == "b")
        #expect(buf[VTPosition(row: 1, column: 3)].character == " ")
    }

    @Test func textEditNarrowFrameDoesNotPaintCJKOutside() async throws {
        final class Box: @unchecked Sendable { var text = "中" }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(
                    text: Binding(get: { box.text }, set: { box.text = $0 })
                )
                .frame(width: 1, height: 1)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 10, height: 4))
        try await app.testing_drainUntilIdle()

        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        #expect(editor.layer.frame.size.width.intValue == 1)

        // Draw into a wider buffer than the editor frame. Pre-fill sentinel so
        // any spill past width=1 would overwrite column 1.
        let drawSize = Size(width: 4, height: 1)
        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: drawSize))
        for col in 0 ..< drawSize.width.intValue {
            buffer.setCell(Cell(char: "#"), at: Position(column: Extended(col), line: 0))
        }
        editor.draw(into: &buffer)

        #expect(
            buffer.character(at: Position(column: 0, line: 0)) != Character("中"),
            "width-1 frame must clip CJK (needs 2 columns)"
        )
        #expect(
            buffer.character(at: Position(column: 1, line: 0)) == Character("#"),
            "must not paint lead/continuation past frame width"
        )
        #expect(buffer.character(at: Position(column: 1, line: 0)) != Character("\u{0000}"))
    }
}

@MainActor
private func findTextEdit(in control: Element?) -> Element? {
    guard let control else { return nil }
    let name = String(describing: type(of: control))
    if name.contains("TextEditor") || name.contains("TextEdit") { return control }
    for child in control.children {
        if let found = findTextEdit(in: child) { return found }
    }
    return nil
}
