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

    /// Writing onto a continuation cell must stay on the requested column
    /// (upper layer wins in place); the straddled wide char's lead is blanked.
    /// The old "retreat to lead" shifted sheet/popup borders one cell left.
    @Test func screenBufferWriteOnContinuationStaysInPlaceAndBlanksLead() {
        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: Size(width: 4, height: 1))
        )
        buffer.setCell(Cell(char: "中"), at: Position(column: 0, line: 0))
        // Write onto the continuation column — like a panel border landing on
        // the second half of an underlying CJK char.
        buffer.setCell(Cell(char: "b"), at: Position(column: 1, line: 0))
        #expect(
            buffer.character(at: Position(column: 0, line: 0)) == Character(" "),
            "straddled lead must be blanked"
        )
        #expect(
            buffer.character(at: Position(column: 1, line: 0)) == Character("b"),
            "new char must stay on its requested column"
        )
    }

    /// Sheet-border shape: the blanked lead keeps the *underlying* style so
    /// panel colors never bleed outside the border.
    @Test func screenBufferBlankedLeadKeepsUnderlyingStyle() {
        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: Size(width: 4, height: 1))
        )
        var under = Cell(char: "中")
        under.backgroundColor = .red
        buffer.setCell(under, at: Position(column: 0, line: 0))

        var border = Cell(char: "│")
        border.backgroundColor = .blue
        buffer.setCell(border, at: Position(column: 1, line: 0))

        let lead = buffer.cell(at: Position(column: 0, line: 0))
        #expect(lead?.char == " ")
        #expect(lead?.backgroundColor == .red, "blank must keep the lower layer's style")
        let borderCell = buffer.cell(at: Position(column: 1, line: 0))
        #expect(borderCell?.char == "│")
        #expect(borderCell?.backgroundColor == .blue)
    }

    /// Wide char written one column off another wide char: the second half of
    /// the lower char becomes an orphaned continuation and must be blanked.
    @Test func screenBufferWideOverWideClearsOrphanContinuation() {
        var buffer = ScreenBuffer(
            rect: Rect(position: .zero, size: Size(width: 4, height: 1))
        )
        // Lower: 中 at columns 1–2.
        buffer.setCell(Cell(char: "中"), at: Position(column: 1, line: 0))
        // Upper: 文 at columns 0–1 — its continuation replaces 中's lead.
        buffer.setCell(Cell(char: "文"), at: Position(column: 0, line: 0))

        #expect(buffer.character(at: Position(column: 0, line: 0)) == Character("文"))
        #expect(buffer.character(at: Position(column: 1, line: 0)) == Character("\u{0000}"))
        #expect(
            buffer.character(at: Position(column: 2, line: 0)) == Character(" "),
            "orphaned continuation of the straddled lower char must be blanked"
        )
    }

    /// Integration: a sheet presented over full-width CJK rows (half the rows
    /// shifted by one column so both column parities straddle the panel edge).
    /// The rounded-border rectangle must stay perfectly aligned — the old
    /// retreat-to-lead write shifted border cells one column left on rows
    /// where an underlying wide char straddled the border column.
    @Test func sheetBorderStaysRectangularOverCJKUnderlay() async throws {
        struct Root: View {
            @State var show = true
            var body: some View {
                VStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { i in
                        Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 19))
                    }
                }
                .sheet(isPresented: $show) {
                    Text("面板内容")
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 12))
        try await app.testing_drainUntilIdle()

        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)

        func find(_ char: Character) -> [Position] {
            var found: [Position] = []
            for line in 0 ..< app.window.layer.frame.size.height.intValue {
                for column in 0 ..< app.window.layer.frame.size.width.intValue {
                    let pos = Position(column: Extended(column), line: Extended(line))
                    if buffer.character(at: pos) == char { found.append(pos) }
                }
            }
            return found
        }

        let topLeft = try #require(find("╭").first)
        let topRight = try #require(find("╮").first)
        let bottomLeft = try #require(find("╰").first)
        let bottomRight = try #require(find("╯").first)

        #expect(topLeft.column == bottomLeft.column, "left border must be a straight column")
        #expect(topRight.column == bottomRight.column, "right border must be a straight column")
        #expect(topLeft.line == topRight.line)
        #expect(bottomLeft.line == bottomRight.line)

        for line in (topLeft.line.intValue + 1) ..< bottomLeft.line.intValue {
            let left = buffer.character(at: Position(column: topLeft.column, line: Extended(line)))
            let right = buffer.character(at: Position(column: topRight.column, line: Extended(line)))
            #expect(left == "│", "row \(line): left border broken, got \(String(describing: left))")
            #expect(right == "│", "row \(line): right border broken, got \(String(describing: right))")
        }
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
