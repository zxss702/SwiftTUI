import Foundation
import Testing
@testable import SwiftTUI

/// TextEdit 硬换行：无幽灵空行；真实空行可放置光标并输入。
@Suite(.serialized)
@MainActor
struct TextEditNewlineTests {
    @Test func enterDoesNotInsertPhantomBlankBeforeNextLine() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(text: Binding(get: { box.text }, set: { box.text = $0 }))
                    .frame(width: 40, height: 6)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 50, height: 10))
        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in Array("hello") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        for ch in Array("world") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_drainUntilIdle()

        #expect(box.text == "hello\nworld")

        let lines = drawnLines(of: editor, height: 3)
        #expect(lines[0].hasPrefix("hello"))
        #expect(lines[1].hasPrefix("world"), "next line must be immediate; got \(lines)")
        #expect(!lines[1].trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test func emptyLineBetweenContentIsEditable() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(text: Binding(get: { box.text }, set: { box.text = $0 }))
                    .frame(width: 40, height: 6)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 50, height: 10))
        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in Array("ab") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        // two Enters → real blank line
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_turn(
            input: .key(KeyEvent(character: "c", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.text == "ab\n\nc")

        let lines = drawnLines(of: editor, height: 4)
        #expect(lines[0].hasPrefix("ab"))
        #expect(lines[1].trimmingCharacters(in: .whitespaces).isEmpty, "middle blank line")
        #expect(lines[2].hasPrefix("c"))
    }

    @Test func caretMovesToNextLineAfterEnter() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(text: Binding(get: { box.text }, set: { box.text = $0 }))
                    .frame(width: 40, height: 6)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 50, height: 10))
        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in Array("hi") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()

        let caret = try #require(editor.cursorPosition)
        #expect(caret.line == 1, "caret after Enter should be on next visual line, got \(caret)")
        #expect(caret.column == 0)
        #expect(box.text == "hi\n")
    }

    @Test func promptOnlyIndentsFirstLine() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(text: Binding(get: { box.text }, set: { box.text = $0 }))
                    .textEditorPrompt("ab>")
                    .frame(width: 40, height: 6)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 50, height: 10))
        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in Array("xy") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\n", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_turn(
            input: .key(KeyEvent(character: "z", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.text == "xy\nz")
        let lines = drawnLines(of: editor, height: 3)
        #expect(lines[0].hasPrefix("ab>xy"), "first line keeps prompt, got \(lines[0])")
        #expect(lines[1].hasPrefix("z"), "continuation starts at column 0, got \(lines[1])")
        #expect(!lines[1].hasPrefix(" "), "no leading space on continuation")

        let caret = try #require(editor.cursorPosition)
        #expect(caret.line == 1)
        #expect(caret.column == 1, "caret after 'z' at col 1, got \(caret)")
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

@MainActor
private func drawnLines(of editor: Element, height: Int) -> [String] {
    let width = max(editor.layer.frame.size.width.intValue, 1)
    var buffer = ScreenBuffer(
        rect: Rect(position: .zero, size: Size(width: Extended(width), height: Extended(height)))
    )
    editor.draw(into: &buffer)
    var lines: [String] = []
    for row in 0 ..< height {
        var s = ""
        for col in 0 ..< width {
            if let ch = buffer.character(at: Position(column: Extended(col), line: Extended(row))),
               ch != "\u{0000}"
            {
                s.append(ch)
            }
        }
        lines.append(s)
    }
    return lines
}
