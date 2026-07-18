import Observation
import Testing
@testable import SwiftTUI

/// Nested `withObservationTracking` must not attribute a child's `@Observable`
/// reads to an ancestor. Otherwise typing in a child `TextEdit` invalidates the
/// whole parent tree (e.g. dialogue + bottom bar).
@Suite(.serialized)
@MainActor
struct ObservationIsolationTests {
    @Observable
    final class Model {
        var flag = 0
        var text = ""
    }

    final class BodyCounter: @unchecked Sendable {
        var parent = 0
        var child = 0
    }

    @Test func childObservableWriteDoesNotInvalidateParentBody() async throws {
        let model = Model()
        let counter = BodyCounter()

        struct Child: View {
            @Bindable var model: Model
            let counter: BodyCounter
            var body: some View {
                let _ = { counter.child += 1 }()
                VStack {
                    Text(model.text.isEmpty ? "empty" : "filled")
                    TextEdit(text: $model.text)
                        .frame(width: 40, height: 3)
                }
            }
        }

        struct Parent: View {
            @Bindable var model: Model
            let counter: BodyCounter
            var body: some View {
                let _ = { counter.parent += 1 }()
                VStack {
                    Text("flag=\(model.flag)")
                    Child(model: model, counter: counter)
                }
            }
        }

        let app = Application(rootView: Parent(model: model, counter: counter))
        try await app.testing_prepare(size: Size(width: 50, height: 12))

        // Force a parent update after the child is built. With the old nested
        // tracking bug, this would register `text` on the parent access list.
        model.flag += 1
        try await app.testing_drainUntilIdle()
        let parentAfterFlag = counter.parent
        let childAfterFlag = counter.child
        #expect(parentAfterFlag >= 2)
        #expect(childAfterFlag >= 2)

        let field = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        try await app.testing_turn(
            input: .key(KeyEvent(character: "x", keycode: 0, modifiers: [], type: .press))
        )

        #expect(counter.parent == parentAfterFlag, "parent must not re-evaluate on child text")
        #expect(counter.child > childAfterFlag, "child that reads text must refresh")
        #expect(findText(in: app.testing_rootElement, equalTo: "filled") != nil)
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
