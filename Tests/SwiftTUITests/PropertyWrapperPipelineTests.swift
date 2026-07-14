import Testing
@testable import SwiftTUI

/// Behavioral: State / FocusState / Binding invalidate through the host.
@Suite(.serialized)
@MainActor
struct PropertyWrapperPipelineTests {

    @Test func stateInvalidatesSameTurn() async throws {
        struct Root: View {
            @State var n = 0
            var body: some View {
                VStack {
                    Text("n=\(n)")
                    Button("inc") { n += 1 }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("inc", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "n=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func bindingConstantIgnoresWrites() async throws {
        struct Root: View {
            var body: some View {
                Toggle(isOn: .constant(true)) { Text("t") }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let toggle = try #require(findButton(in: app.testing_rootElement))
        try await click(toggle, on: app)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func focusStateRoundsTrip() async throws {
        struct Root: View {
            @FocusState var focused: Bool
            @State var text = ""
            var body: some View {
                VStack {
                    TextField("f", text: $text)
                        .focused($focused)
                    Text(focused ? "focused" : "blurred")
                    Button("focus") { focused = true }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("focus", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "focused") != nil)
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
