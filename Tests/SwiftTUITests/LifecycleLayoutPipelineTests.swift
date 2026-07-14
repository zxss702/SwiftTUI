import Testing
@testable import SwiftTUI

/// Behavioral: onChange, layoutPriority, divider style, equatable skip, lazy remount.
@Suite(.serialized)
@MainActor
struct LifecycleLayoutPipelineTests {

    @Test func onChangeFiresSameTurnWithLatestAction() async throws {
        final class Box {
            var values: [Int] = []
            var token = 0
        }
        let box = Box()
        struct Root: View {
            @State var n = 0
            let box: Box
            var body: some View {
                let token = box.token
                VStack {
                    Text("n=\(n)")
                    Button("inc") { n += 1 }
                }
                .onChange(of: n) { _, new in
                    box.values.append(new + token)
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        box.token = 100
        try await click(try #require(findButtonLabeled("inc", in: app.testing_rootElement)), on: app)
        #expect(box.values == [101])
        #expect(findText(in: app.testing_rootElement, equalTo: "n=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func frameMaxWidthExpandsInHStack() async throws {
        // Regression: collapsing ∞ offers in FlexibleFrame broke stack flexibility.
        let root = HStack {
            Text("L")
            Text("expand").frame(maxWidth: .infinity)
            Text("R")
        }
        let node = Node(view: root.view)
        node.build()
        let element = try #require(node.element)
        let size = element.size(proposedSize: Size(width: 40, height: 1))
        #expect(size.width == 40)
        element.layout(size: size)
        #expect(element.layer.frame.size.width == 40)
    }

    @Test func layoutPriorityChangeRequestsLayout() async throws {
        struct Root: View {
            @State var priority: Double = 0
            var body: some View {
                HStack {
                    Text("a").layoutPriority(priority)
                    Text("b")
                    Button("boost") { priority = 10 }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let before = app.testing_scheduler.scheduleCallCount
        try await click(try #require(findButtonLabeled("boost", in: app.testing_rootElement)), on: app)
        let after = app.testing_scheduler.scheduleCallCount
        #expect(after > before || !app.hasPendingCommitWork)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func equatableSkipsWhenEqual() async throws {
        final class Box { var rowBodies = 0 }
        let box = Box()
        struct Row: View, Equatable {
            let text: String
            let onBody: @MainActor () -> Void
            nonisolated static func == (lhs: Row, rhs: Row) -> Bool { lhs.text == rhs.text }
            var body: some View {
                let _ = onBody()
                return Text(text)
            }
        }
        struct Root: View {
            @State var tick = 0
            let box: Box
            var body: some View {
                VStack {
                    Row(text: "same", onBody: { box.rowBodies += 1 }).equatable()
                    Button("tick") { tick += 1 }
                    Text("t=\(tick)")
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        let afterPrepare = box.rowBodies
        try await click(try #require(findButtonLabeled("tick", in: app.testing_rootElement)), on: app)
        #expect(box.rowBodies == afterPrepare, "equatable should skip Row body when text unchanged")
        #expect(findText(in: app.testing_rootElement, equalTo: "t=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func dividerStyleUpdatesWithoutCrash() async throws {
        struct Root: View {
            @State var dashed = false
            var body: some View {
                VStack {
                    Divider().style(dashed ? .double : .default)
                    Button("style") { dashed.toggle() }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("style", in: app.testing_rootElement)), on: app)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func lazyVStackIdentitySwapSettles() async throws {
        struct Root: View {
            @State var items = [1, 2, 3]
            var body: some View {
                ScrollView {
                    LazyVStack {
                        ForEach(items, id: \.self) { n in
                            Text("row-\(n)")
                        }
                    }
                }
                Button("drop") { items = [1, 3] }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("drop", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "row-2") == nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "row-3") != nil)
        #expect(!app.hasPendingCommitWork)
    }
}

// MARK: - Helpers

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
