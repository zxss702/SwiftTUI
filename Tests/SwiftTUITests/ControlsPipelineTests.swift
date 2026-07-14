import Testing
@testable import SwiftTUI

/// Behavioral: Controls Binding / selection sync on the new host.
@Suite(.serialized)
@MainActor
struct ControlsPipelineTests {

    @Test func toggleBindingSameTurn() async throws {
        struct Root: View {
            @State var on = false
            var body: some View {
                VStack {
                    Text(on ? "ON" : "OFF")
                    Toggle(isOn: $on) { Text("flip") }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let toggle = try #require(findButtonLabeled("flip", in: app.testing_rootElement)
            ?? findButton(in: app.testing_rootElement))
        try await click(toggle, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "ON") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func stepperIncrementsBinding() async throws {
        struct Root: View {
            @State var n = 0
            var body: some View {
                VStack {
                    Text("n=\(n)")
                    Stepper(value: $n, in: 0 ... 10) { Text("step") }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        // StepperElement is selectable — activate with '+' / space after focus.
        let stepper = try #require(findStepper(in: app.testing_rootElement))
        app.window.setFirstResponder(stepper)
        try await app.testing_turn(input: .key(KeyEvent(character: "+", keycode: 0, modifiers: [], type: .press)))
        #expect(findText(in: app.testing_rootElement, equalTo: "n=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func pickerSelectionUpdatesLabel() async throws {
        struct Root: View {
            @State var selection = 1
            var body: some View {
                VStack {
                    Picker("p", selection: $selection) {
                        Text("one").tag(1)
                        Text("two").tag(2)
                    }
                    .pickerStyle(.inline)
                    Button("sel2") { selection = 2 }
                    Text("sel=\(selection)")
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("sel2", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "sel=2") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func secureFieldAcceptsInput() async throws {
        final class Box { var text = "" }
        let box = Box()
        struct Root: View {
            @State var text = ""
            let box: Box
            var body: some View {
                let _ = { box.text = text }()
                SecureField("pw", text: $text)
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        let field = try #require(findTextField(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        for ch in ["a", "b"] {
            try await app.testing_turn(input: .key(KeyEvent(character: Character(ch), keycode: 0, modifiers: [], type: .press)))
        }
        #expect(box.text == "ab")
        #expect(!app.hasPendingCommitWork)
    }

    @Test func progressAndSpacerIdle() async throws {
        let app = Application(rootView: VStack {
            ProgressView(value: 0.5)
            ProgressView()
            Spacer()
            Color.red.frame(width: 2, height: 1)
        })
        try await app.testing_prepare()
        #expect(!app.hasPendingCommitWork)
    }
}

// MARK: - Helpers

@MainActor
private func findButton(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("Button") { return control }
    for child in control.children {
        if let found = findButton(in: child) { return found }
    }
    return nil
}

@MainActor
private func findStepper(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("Stepper") { return control }
    for child in control.children {
        if let found = findStepper(in: child) { return found }
    }
    return nil
}

@MainActor
private func findTextField(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("TextField") { return control }
    for child in control.children {
        if let found = findTextField(in: child) { return found }
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
private func findText(in control: Element?, equalTo target: String) -> Element? {
    guard let control else { return nil }
    if textLabel(in: control) == target { return control }
    for child in control.children {
        if let found = findText(in: child, equalTo: target) { return found }
    }
    return nil
}

@MainActor
private func findButtonLabeled(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"), textLabel(in: root) == label {
        return root
    }
    for child in root.children {
        if let found = findButtonLabeled(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func center(of control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
}

@MainActor
private func click(_ button: Element, on app: Application) async throws {
    app.window.setFirstResponder(button)
    let pos = center(of: button)
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
}
