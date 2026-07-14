import Testing
@testable import SwiftTUI

/// Behavioral: modifiers / stacks / structural views on the new host.
@Suite(.serialized)
@MainActor
struct ModifiersPipelineTests {

    @Test func disabledBlocksButtonActivation() async throws {
        final class Box { var hits = 0 }
        let box = Box()
        struct Root: View {
            @State var disabled = true
            let box: Box
            var body: some View {
                VStack {
                    Button("go") { box.hits += 1 }
                        .disabled(disabled)
                    Button("enable") { disabled = false }
                    Text("hits=\(box.hits)")
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        if let go = findButtonLabeled("go", in: app.testing_rootElement) {
            try await click(go, on: app)
        }
        #expect(box.hits == 0)
        try await click(try #require(findButtonLabeled("enable", in: app.testing_rootElement)), on: app)
        try await click(try #require(findButtonLabeled("go", in: app.testing_rootElement)), on: app)
        #expect(box.hits == 1)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func onAppearRunsDuringPrepare() async throws {
        final class Box { var appeared = false }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Text("x").onAppear { box.appeared = true }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        #expect(box.appeared)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func taskCancelsOnDisappear() async throws {
        final class Box: @unchecked Sendable {
            var started = false
            var cancelled = false
        }
        let box = Box()
        struct Root: View {
            @State var show = true
            let box: Box
            var body: some View {
                VStack {
                    if show {
                        Text("task")
                            .task {
                                box.started = true
                                while !Task.isCancelled {
                                    try? await Task.sleep(for: .milliseconds(20))
                                }
                                box.cancelled = true
                            }
                    }
                    Button("hide") { show = false }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        for _ in 0 ..< 20 where !box.started {
            try await Task.sleep(for: .milliseconds(10))
            try await app.testing_turn()
        }
        #expect(box.started)
        try await click(try #require(findButtonLabeled("hide", in: app.testing_rootElement)), on: app)
        // Allow cancellation to land on the cancelled task.
        for _ in 0 ..< 20 where !box.cancelled {
            try await Task.sleep(for: .milliseconds(25))
            try await app.testing_turn()
        }
        #expect(box.cancelled)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func forEachInsertRemoveSettles() async throws {
        struct Root: View {
            @State var items = ["a", "b"]
            var body: some View {
                VStack {
                    ForEach(items, id: \.self) { Text($0) }
                    Button("add") { items.append("c") }
                    Button("drop") { items.removeLast() }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("add", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "c") != nil)
        try await click(try #require(findButtonLabeled("drop", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "c") == nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func paddingAndFrameSettle() async throws {
        struct Root: View {
            @State var padded = false
            var body: some View {
                Text("x")
                    .padding(padded ? 2 : 0)
                    .frame(width: 10)
                    .border()
                Button("pad") { padded = true }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("pad", in: app.testing_rootElement)), on: app)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func overlayAndBackgroundCompose() async throws {
        let app = Application(rootView:
            Text("base")
                .background { Text("bg") }
                .overlay { Text("ov") }
        )
        try await app.testing_prepare()
        #expect(findText(in: app.testing_rootElement, equalTo: "base") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "bg") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "ov") != nil)
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
