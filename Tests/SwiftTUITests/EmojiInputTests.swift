import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct EmojiInputTests {

    @Test func characterWidthForCommonEmoji() {
        #expect("😀".first!.width == 2)
        #expect("中".first!.width == 2)
        #expect("a".first!.width == 1)
        // Variation-selector emoji presentation must be double-width in terminals
        #expect("⭐️".first!.width == 2, "got \("⭐️".first!.width)")
        #expect("❤️".first!.width == 2, "got \("❤️".first!.width)")
        #expect("✅".first!.width == 2, "got \("✅".first!.width)")
        // ZWJ / skin-tone sequences are one Character, still one double cell
        #expect("👍🏻".first!.width == 2, "got \("👍🏻".first!.width)")
        #expect("👨‍👩‍👧".first!.width == 2, "got \("👨‍👩‍👧".first!.width)")
        // String.width must match sum of Character widths (not scalar widths)
        let s = "a👍🏻中😀"
        let byChar = s.reduce(0) { $0 + $1.width }
        #expect(s.width == byChar, "String.width=\(s.width) byChar=\(byChar)")
    }

    @Test func textFieldAcceptsEmojiWithoutCrash() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct V: View {
            let b: Binding<String>
            var body: some View { TextField("t", text: b) }
        }
        let app = Application(rootView: V(b: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 40, height: 5))
        let field = findTF(app.testing_rootElement)!
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in ["a", "😀", "中", "👍🏻", "⭐️"] {
            try await app.testing_turn(
                input: .key(KeyEvent(character: Character(ch), keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_drainUntilIdle()
        #expect(box.text.contains("😀"))
        #expect(box.text.contains("⭐️") || box.text.contains("⭐"), "got \(box.text.debugDescription)")
        if let pos = field.cursorPosition {
            #expect(pos.column >= 0)
            #expect(pos.column <= field.layer.frame.size.width)
        }
    }

    /// ZWJ / VS16 merge into the previous grapheme; a naive `cursor += 1`
    /// used to leave the cursor past `count` and crash on the next keystroke.
    @Test func textFieldEmojiCompositionDoesNotCorruptCursor() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct V: View {
            let b: Binding<String>
            var body: some View { TextField("t", text: b) }
        }
        let app = Application(rootView: V(b: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 40, height: 5))
        let field = findTF(app.testing_rootElement)!
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        try await app.testing_turn(
            input: .key(KeyEvent(character: "👍", keycode: 0, modifiers: [], type: .press))
        )
        // Skin tone modifier — merges into previous Character.
        try await app.testing_turn(
            input: .key(KeyEvent(character: "\u{1F3FB}", keycode: 0, modifiers: [], type: .press))
        )
        // Must not crash on the next printable character.
        try await app.testing_turn(
            input: .key(KeyEvent(character: "x", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()
        #expect(box.text.contains("x"))
        #expect(box.text.count >= 2)
    }

    @Test func textEditorAcceptsEmojiWithoutCrash() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct V: View {
            let b: Binding<String>
            var body: some View { TextEditor(text: b) }
        }
        let app = Application(rootView: V(b: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 20, height: 6))
        let editor = findTE(app.testing_rootElement)!
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in Array("hello😀世界👍🏻⭐️") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        // Compose a ZWJ family emoji one scalar-cluster at a time.
        for ch: Character in ["👨", "\u{200D}", "👩", "\u{200D}", "👧"] {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_turn(
            input: .key(KeyEvent(character: "!", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()
        #expect(box.text.contains("😀"))
        #expect(box.text.contains("!"))
    }

    @Test func textEditorNarrowWidthEmojiDoesNotTrap() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct V: View {
            let b: Binding<String>
            var body: some View {
                TextEditor(text: b).frame(width: Extended(1), height: Extended(3))
            }
        }
        let app = Application(rootView: V(b: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 10, height: 6))
        let editor = findTE(app.testing_rootElement)!
        app.window.setFirstResponder(editor)
        try await app.testing_turn()
        try await app.testing_turn(
            input: .key(KeyEvent(character: "😀", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()
        #expect(box.text.contains("😀"))
    }

    @Test func cursorColumnTracksEmojiWidth() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct V: View {
            let b: Binding<String>
            var body: some View { TextField("t", text: b) }
        }
        let app = Application(rootView: V(b: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 40, height: 5))
        let field = findTF(app.testing_rootElement)!
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        try await app.testing_turn(
            input: .key(KeyEvent(character: "⭐️", keycode: 0, modifiers: [], type: .press))
        )
        try await app.testing_drainUntilIdle()
        let pos = try #require(field.cursorPosition)
        #expect(pos.column == 2, "cursor after ⭐️ should be column 2, got \(pos.column)")
    }
}

@MainActor
private func findTF(_ c: Element?) -> Element? {
    guard let c else { return nil }
    if c is TextFieldElement { return c }
    for ch in c.children { if let f = findTF(ch) { return f } }
    return nil
}

@MainActor
private func findTE(_ c: Element?) -> Element? {
    guard let c else { return nil }
    if String(describing: type(of: c)).contains("TextEditorElement") { return c }
    for ch in c.children { if let f = findTE(ch) { return f } }
    return nil
}
