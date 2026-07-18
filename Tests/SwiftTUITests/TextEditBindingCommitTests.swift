import Testing
@testable import SwiftTUI

/// TextEdit：内容变化必须写 Binding；粘贴合并为一次插入。
@Suite(.serialized)
@MainActor
struct TextEditBindingCommitTests {
    @Test func clearingContentUpdatesBindingAndDependentViews() async throws {
        struct Root: View {
            @State var text = "hello"
            var body: some View {
                VStack {
                    if text.isEmpty {
                        Text("empty")
                    } else {
                        Text("filled")
                    }
                    TextEdit(text: $text)
                        .frame(width: 40, height: 3)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 50, height: 12))
        #expect(findText(in: app.testing_rootElement, equalTo: "filled") != nil)

        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)

        for _ in 0 ..< 5 {
            try await app.testing_turn(
                input: .key(KeyEvent(character: "\u{7F}", keycode: 0, modifiers: [], type: .press))
            )
        }

        #expect(findText(in: app.testing_rootElement, equalTo: "empty") != nil)
    }

    @Test func externalBindingClearSyncsEditor() async throws {
        struct Root: View {
            @State var text = "seed"
            var body: some View {
                VStack {
                    Button("clear") { text = "" }
                    TextEdit(text: $text)
                        .frame(width: 40, height: 3)
                    Text(text.isEmpty ? "empty" : "filled")
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 50, height: 12))
        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)

        try await app.testing_turn(
            input: .key(KeyEvent(character: "x", keycode: 0, modifiers: [], type: .press))
        )
        #expect(findText(in: app.testing_rootElement, equalTo: "filled") != nil)

        let clear = try #require(findButtonLabeled("clear", in: app.testing_rootElement))
        try await click(clear, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "empty") != nil)
    }

    @Test func coalescedPasteWritesBindingOnceWithFullText() async throws {
        final class Box {
            var text = ""
            var setCount = 0
            var lastSet = ""
        }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                TextEdit(
                    text: Binding(
                        get: { box.text },
                        set: {
                            box.text = $0
                            box.setCount += 1
                            box.lastSet = $0
                        }
                    )
                )
                .frame(width: 40, height: 5)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 50, height: 12))
        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)

        let pasted = "hello paste world"
        let keys: [VTEvent] = pasted.map {
            .key(KeyEvent(character: $0, keycode: 0, modifiers: [], type: .press))
        }
        let coalesced = VTEvent.coalescingTerminalEvents(keys)
        #expect(coalesced.count == 1)
        guard case .textInput(let bulk) = coalesced[0] else {
            Issue.record("expected single textInput, got \(coalesced)")
            return
        }
        #expect(bulk == pasted)

        let setsBefore = box.setCount
        try await app.testing_turn(input: .textInput(bulk))
        #expect(box.text == pasted)
        #expect(box.lastSet == pasted)
        #expect(box.setCount - setsBefore == 1, "paste must write Binding once, not per character")
    }

    @Test func emptyToNonEmptyStillRebuildsForLayout() async throws {
        struct Root: View {
            @State var text = ""
            var body: some View {
                VStack {
                    if text.isEmpty {
                        Text("empty")
                    } else {
                        Text("filled")
                    }
                    TextEdit(text: $text)
                        .frame(width: 40, height: 3)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 50, height: 12))
        #expect(findText(in: app.testing_rootElement, equalTo: "empty") != nil)

        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)

        try await app.testing_turn(
            input: .key(KeyEvent(character: "x", keycode: 0, modifiers: [], type: .press))
        )
        #expect(findText(in: app.testing_rootElement, equalTo: "filled") != nil)
    }

    /// 滚到底后外部清空：contentOffset 必须钳位，draw 不得因非法 Range 崩溃。
    @Test func scrollThenExternalClearDoesNotCrashDraw() async throws {
        struct Root: View {
            @State var text = String(repeating: "line\n", count: 40)
            var body: some View {
                VStack {
                    Button("clear") { text = "" }
                    TextEdit(text: $text)
                        .frame(width: 40, height: 3)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 50, height: 12))
        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)

        let pos = field.absoluteFrame.position
        for _ in 0 ..< 30 {
            try await app.testing_turn(
                input: .mouse(MouseEvent(position: pos, type: .scroll(deltaX: 0, deltaY: 1)))
            )
        }

        let clear = try #require(findButtonLabeled("clear", in: app.testing_rootElement))
        try await click(clear, on: app)
        try await app.testing_drainUntilIdle()
        #expect(findTextEdit(in: app.testing_rootElement) != nil)
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
private func findText(in control: Element?, equalTo value: String) -> Element? {
    guard let control else { return nil }
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String,
       text == value
    {
        return control
    }
    for child in control.children {
        if let found = findText(in: child, equalTo: value) { return found }
    }
    return nil
}

@MainActor
private func findButtonLabeled(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"),
       textLabel(in: root) == label
    {
        return root
    }
    for child in root.children {
        if let found = findButtonLabeled(label, in: child) { return found }
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

@MainActor
private func click(_ element: Element, on app: Application) async throws {
    let frame = element.absoluteFrame
    let pos = Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .pressed(.left)))
    )
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .released(.left)))
    )
}
