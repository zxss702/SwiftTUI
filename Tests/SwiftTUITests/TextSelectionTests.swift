import Foundation
import Testing
@testable import SwiftTUI

/// Text selection: drag/shift-arrow selection, replace/delete, cut, undo/redo,
/// `.selectable()` regions, and the application-wide unique-selection rule.
@Suite(.serialized)
@MainActor
struct TextSelectionTests {

    // MARK: - Helpers

    private func keyEvent(
        _ character: Character?,
        keycode: UInt16 = 0,
        modifiers: KeyModifiers = []
    ) -> VTEvent {
        .key(KeyEvent(character: character, keycode: keycode, modifiers: modifiers, type: .press))
    }

    private func drag(_ app: Application, from: Position, to: Position) async throws {
        try await app.testing_turn(input: .mouse(MouseEvent(position: from, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .move)))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .released(.left))))
    }

    private func click(_ app: Application, at position: Position) async throws {
        try await app.testing_turn(input: .mouse(MouseEvent(position: position, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: position, type: .released(.left))))
    }

    private final class Box: @unchecked Sendable {
        var text = ""
        init(_ text: String = "") { self.text = text }
    }

    private struct FieldView: View {
        let binding: Binding<String>
        var body: some View {
            TextField("type", text: binding)
        }
    }

    private struct EditorView: View {
        let binding: Binding<String>
        var body: some View {
            TextEditor(text: binding)
        }
    }

    private func makeFieldApp(_ box: Box) async throws -> (Application, Element) {
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let app = Application(rootView: FieldView(binding: binding))
        try await app.testing_prepare()
        let field = try #require(findElement(in: app.testing_rootElement, typeContains: "TextFieldElement"))
        return (app, field)
    }

    // MARK: - TextField

    @Test func textFieldDragSelectionTypingReplaces() async throws {
        let box = Box("hello world")
        let (app, field) = try await makeFieldApp(box)
        let origin = field.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 5, line: 0))
        let owner = try #require(field as? SelectionOwner)
        #expect(owner.selectedText() == "hello")
        #expect(app.window.selectionCoordinator.activeOwner === owner)

        try await app.testing_turn(input: keyEvent("X"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "X world", "got \(box.text.debugDescription)")
        #expect(owner.selectedText() == nil)
    }

    @Test func textFieldSelectionBackspaceDeletes() async throws {
        let box = Box("hello world")
        let (app, field) = try await makeFieldApp(box)
        let origin = field.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 6, line: 0))
        try await app.testing_turn(input: keyEvent("\u{7f}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "world", "got \(box.text.debugDescription)")
    }

    @Test func textFieldShiftArrowSelectsAndCtrlXCuts() async throws {
        let box = Box("hello")
        let (app, field) = try await makeFieldApp(box)
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        // Cursor starts at the end; Shift+Left twice selects "lo".
        try await app.testing_turn(input: keyEvent(nil, keycode: VTKeyCode.left, modifiers: [.shift]))
        try await app.testing_turn(input: keyEvent(nil, keycode: VTKeyCode.left, modifiers: [.shift]))
        let owner = try #require(field as? SelectionOwner)
        #expect(owner.selectedText() == "lo")

        // Ctrl+X (raw control byte, headless clipboard is a no-op).
        try await app.testing_turn(input: keyEvent("\u{18}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "hel", "got \(box.text.debugDescription)")
    }

    @Test func textFieldUndoRedo() async throws {
        let box = Box("")
        let (app, field) = try await makeFieldApp(box)
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in "abc" {
            try await app.testing_turn(input: keyEvent(ch))
        }
        try await app.testing_drainUntilIdle()
        #expect(box.text == "abc")

        // Coalesced typing group undoes in one step (Ctrl+Z).
        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "", "undo should revert the whole typing run, got \(box.text.debugDescription)")

        // Redo (Ctrl+Y).
        try await app.testing_turn(input: keyEvent("\u{19}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "abc", "redo failed, got \(box.text.debugDescription)")
    }

    /// Latin text undoes word by word (split at spaces).
    @Test func textFieldUndoIsWordLevelForLatin() async throws {
        let box = Box("")
        let (app, field) = try await makeFieldApp(box)
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in "ab cd" {
            try await app.testing_turn(input: keyEvent(ch))
        }
        try await app.testing_drainUntilIdle()
        #expect(box.text == "ab cd")

        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "ab ", "first undo should drop the last word, got \(box.text.debugDescription)")

        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "", "second undo should drop the first word, got \(box.text.debugDescription)")
    }

    /// CJK (and other wide characters) undo one character at a time.
    @Test func textFieldUndoIsCharacterLevelForCJK() async throws {
        let box = Box("")
        let (app, field) = try await makeFieldApp(box)
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in "中文" {
            try await app.testing_turn(input: keyEvent(ch))
        }
        try await app.testing_drainUntilIdle()
        #expect(box.text == "中文")

        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "中", "undo should drop one CJK character, got \(box.text.debugDescription)")

        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "", "got \(box.text.debugDescription)")
    }

    /// The soft caret hides while a selection is active.
    @Test func caretHiddenDuringSelection() async throws {
        let box = Box("hello")
        let (app, field) = try await makeFieldApp(box)
        app.window.setFirstResponder(field)
        try await app.testing_turn()
        #expect(field.cursorPosition != nil)

        try await app.testing_turn(input: keyEvent(nil, keycode: VTKeyCode.left, modifiers: [.shift]))
        #expect(field.cursorPosition == nil, "caret must hide while selecting")

        // Collapsing the selection brings the caret back.
        try await app.testing_turn(input: keyEvent(nil, keycode: VTKeyCode.left))
        #expect(field.cursorPosition != nil)
    }

    @Test func textFieldSelectionHighlightUsesSelectionColors() async throws {
        let box = Box("hello")
        let (app, field) = try await makeFieldApp(box)
        let origin = field.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 3, line: 0))

        let size = field.layer.frame.size
        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: size))
        field.draw(into: &buffer)

        let selectedCell = try #require(buffer.cell(at: Position(column: 0, line: 0)))
        #expect(selectedCell.backgroundColor == TextSelectionStyle.background)
        #expect(selectedCell.foregroundColor == TextSelectionStyle.foreground)
        let unselectedCell = try #require(buffer.cell(at: Position(column: 4, line: 0)))
        #expect(unselectedCell.backgroundColor == nil)
    }

    // MARK: - TextEditor

    @Test func textEditorDragSelectionReplaceUndoRedo() async throws {
        let box = Box("hello\nworld")
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let app = Application(rootView: EditorView(binding: binding))
        try await app.testing_prepare()
        let editor = try #require(findElement(in: app.testing_rootElement, typeContains: "TextEditorElement"))
        let origin = editor.absoluteFrame.position

        // Select "hello\nwo" (line 0 col 0 → line 1 col 2).
        try await drag(app, from: origin, to: origin + Position(column: 2, line: 1))
        let owner = try #require(editor as? SelectionOwner)
        #expect(owner.selectedText() == "hello\nwo")

        try await app.testing_turn(input: keyEvent("Z"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "Zrld", "got \(box.text.debugDescription)")

        try await app.testing_turn(input: keyEvent("\u{1a}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "hello\nworld", "undo failed, got \(box.text.debugDescription)")

        try await app.testing_turn(input: keyEvent("\u{19}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "Zrld", "redo failed, got \(box.text.debugDescription)")
    }

    @Test func textEditorSelectionDeleteByBackspace() async throws {
        let box = Box("hello world")
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let app = Application(rootView: EditorView(binding: binding))
        try await app.testing_prepare()
        let editor = try #require(findElement(in: app.testing_rootElement, typeContains: "TextEditorElement"))
        let origin = editor.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 6, line: 0))
        try await app.testing_turn(input: keyEvent("\u{7f}"))
        try await app.testing_drainUntilIdle()
        #expect(box.text == "world", "got \(box.text.debugDescription)")
    }

    // MARK: - .selectable()

    @Test func selectableDragCapturesText() async throws {
        let app = Application(rootView: Text("hello world").selectable())
        try await app.testing_prepare()
        let selectable = try #require(
            findElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 4, line: 0))
        #expect(selectable.hasSelection)
        #expect(selectable.selectedText() == "hello")
        #expect(app.window.selectionCoordinator.activeOwner === selectable)

        // The global highlight pass re-styles the final buffer (not the views).
        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)
        app.window.selectionCoordinator.applyHighlight(into: &buffer)
        let selectedCell = try #require(buffer.cell(at: origin))
        #expect(selectedCell.backgroundColor == TextSelectionStyle.background)
        let unselectedCell = try #require(buffer.cell(at: origin + Position(column: 6, line: 0)))
        #expect(unselectedCell.backgroundColor != TextSelectionStyle.background)

        // The next click clears the selection.
        try await click(app, at: origin + Position(column: 8, line: 0))
        #expect(!selectable.hasSelection)
    }

    /// A press anywhere in the UI (even outside the region) cancels the
    /// active selection.
    @Test func clickAnywhereCancelsSelection() async throws {
        struct Root: View {
            var body: some View {
                VStack {
                    Text("selectable line").selectable()
                    Text("plain area")
                    Text("far away")
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let selectable = try #require(
            findElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position
        try await drag(app, from: origin, to: origin + Position(column: 6, line: 0))
        #expect(selectable.hasSelection)

        // Click far below the selectable region.
        try await click(app, at: origin + Position(column: 2, line: 2))
        #expect(!selectable.hasSelection)
        #expect(app.window.selectionCoordinator.activeOwner == nil)
    }

    @Test func selectableCleanClickReachesButton() async throws {
        final class Taps: @unchecked Sendable { var count = 0 }
        let taps = Taps()

        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                VStack {
                    Text("caption")
                    Button("Tap") { onTap() }
                }
                .selectable()
            }
        }

        let app = Application(rootView: Root(onTap: { taps.count += 1 }))
        try await app.testing_prepare()
        let button = try #require(findElement(in: app.testing_rootElement, typeContains: "ButtonElement"))
        let center = button.absoluteFrame.position

        try await click(app, at: center)
        #expect(taps.count == 1, "click did not pass through .selectable(), taps=\(taps.count)")
    }

    @Test func selectionIsUniqueAcrossOwners() async throws {
        let boxA = Box("first field")
        let boxB = Box("second field")

        struct TwoFields: View {
            let a: Binding<String>
            let b: Binding<String>
            var body: some View {
                VStack {
                    TextField("a", text: a)
                    TextField("b", text: b)
                }
            }
        }

        let app = Application(
            rootView: TwoFields(
                a: Binding(get: { boxA.text }, set: { boxA.text = $0 }),
                b: Binding(get: { boxB.text }, set: { boxB.text = $0 })
            )
        )
        try await app.testing_prepare()
        let fields = findAllElements(in: app.testing_rootElement, typeContains: "TextFieldElement")
        #expect(fields.count == 2)
        let first = try #require(fields.first as? SelectionOwner)
        let second = try #require(fields.last as? SelectionOwner)

        let firstOrigin = fields[0].absoluteFrame.position
        try await drag(app, from: firstOrigin, to: firstOrigin + Position(column: 5, line: 0))
        #expect(first.selectedText() == "first")

        let secondOrigin = fields[1].absoluteFrame.position
        try await drag(app, from: secondOrigin, to: secondOrigin + Position(column: 6, line: 0))
        #expect(second.selectedText() == "second")
        #expect(first.selectedText() == nil, "starting a new selection must clear the previous one")
        #expect(app.window.selectionCoordinator.activeOwner === second)
    }

    // MARK: - Parser

    @Test func parserDecodesShiftArrow() throws {
        var parser = VTInputParser()
        // CSI 1;2D = Shift+Left
        let bytes: [UInt8] = [0x1b, 0x5b, 0x31, 0x3b, 0x32, 0x44]
        let sequences = parser.parse(bytes[...])
        #expect(sequences.count == 1)
        let event = try #require(sequences.first?.event)
        #expect(event.keycode == VTKeyCode.left)
        #expect(event.modifiers.contains(.shift))
    }

    @Test func parserPlainArrowHasNoModifiers() throws {
        var parser = VTInputParser()
        let bytes: [UInt8] = [0x1b, 0x5b, 0x44]
        let sequences = parser.parse(bytes[...])
        let event = try #require(sequences.first?.event)
        #expect(event.keycode == VTKeyCode.left)
        #expect(event.modifiers.isEmpty)
    }
}

// MARK: - Tree helpers

@MainActor
private func findElement(in control: Element?, typeContains name: String) -> Element? {
    findAllElements(in: control, typeContains: name).first
}

@MainActor
private func findAllElements(in control: Element?, typeContains name: String) -> [Element] {
    guard let control else { return [] }
    var result: [Element] = []
    if String(describing: type(of: control)).contains(name) {
        result.append(control)
    }
    for child in control.children {
        result.append(contentsOf: findAllElements(in: child, typeContains: name))
    }
    return result
}
