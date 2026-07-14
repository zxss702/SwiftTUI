import Testing
@testable import SwiftTUI

/// Per-family pipeline contracts: one interaction settles; no leftover dirty.
@Suite(.serialized)
@MainActor
struct ViewPipelineTests {

    @Test func vstackButtonStateSettles() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            @State var n = 0
            let onN: (Int) -> Void
            var body: some View {
                let _ = onN(n)
                VStack {
                    Text("count=\(n)")
                    Button("inc") { n += 1 }
                }
            }
        }
        let app = Application(rootView: Root(onN: { box.n = $0 }))
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.n == 1)
        #expect(findText(in: app.testing_rootElement, equalTo: "count=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func hstackToggleViaButtonSettles() async throws {
        final class Box { var on = false }
        let box = Box()
        struct Root: View {
            @State var on = false
            let report: (Bool) -> Void
            var body: some View {
                let _ = report(on)
                HStack {
                    Text(on ? "ON" : "OFF")
                    Button("flip") { on.toggle() }
                }
            }
        }
        let app = Application(rootView: Root(report: { box.on = $0 }))
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.on)
        #expect(findText(in: app.testing_rootElement, equalTo: "ON") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func zstackKeepsIdleAfterPrepare() async throws {
        let app = Application(rootView: ZStack {
            Text("a")
            Text("b")
        })
        try await app.testing_prepare()
        #expect(!app.hasPendingCommitWork)
        let extra = try await app.testing_drainUntilIdle(maxCommits: 8)
        #expect(extra == 0)
    }

    @Test func scrollViewAcceptsScrollEvent() async throws {
        let app = Application(rootView: ScrollView {
            VStack {
                ForEach(0 ..< 20, id: \.self) { i in
                    Text("row-\(i)")
                }
            }
        })
        try await app.testing_prepare()
        try await app.testing_turn(
            input: .mouse(MouseEvent(
                position: Position(x: 5, y: 5),
                type: .scroll(deltaX: 0, deltaY: 3)
            ))
        )
        #expect(!app.hasPendingCommitWork)
    }
}

// Local helpers (duplicated lightly to keep suites independent)

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
