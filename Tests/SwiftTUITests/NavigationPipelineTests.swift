import Testing
@testable import SwiftTUI

/// Behavioral: NavigationStack keep-alive, title/toolbar page binding, push/pop state.
@Suite(.serialized)
@MainActor
struct NavigationPipelineTests {

    @Test func pushPopPreservesRootState() async throws {
        struct Root: View {
            @State var counter = 0
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("count=\(counter)")
                        Button("inc") { counter += 1 }
                        NavigationLink("go", value: 1)
                    }
                    .navigationTitle("Home")
                    .navigationDestination(for: Int.self) { n in
                        Text("page \(n)")
                            .navigationTitle("P\(n)")
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()

        let inc = try #require(findButtonLabeled("inc", in: app.testing_rootElement))
        try await click(inc, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "count=1") != nil)

        let go = try #require(findButtonLabeled("go", in: app.testing_rootElement))
        try await click(go, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "page 1") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "P1") != nil)

        let back = try #require(findButtonLabeled("⟨Home", in: app.testing_rootElement)
            ?? findButtonLabeled("⟨返回", in: app.testing_rootElement))
        try await click(back, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "count=1") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func titleUpdatesSameTurnWithoutFrameStorm() async throws {
        struct Root: View {
            @State var title = "A"
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("body")
                        Button("rename") { title = "B" }
                    }
                    .navigationTitle(title)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(findText(in: app.testing_rootElement, equalTo: "A") != nil)

        let rename = try #require(findButtonLabeled("rename", in: app.testing_rootElement))
        let before = app.testing_scheduler.scheduleCallCount
        try await click(rename, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "B") != nil)
        let after = app.testing_scheduler.scheduleCallCount
        #expect(after - before <= 4, "title update scheduled unbounded wakes")
        #expect(!app.hasPendingCommitWork)
    }

    @Test func toolbarBoundToPageDoesNotLeakAcrossPush() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("home")
                        NavigationLink("go", value: 1)
                    }
                    .navigationTitle("Home")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("HomeEdit") {}
                        }
                    }
                    .navigationDestination(for: Int.self) { _ in
                        Text("detail")
                            .navigationTitle("Detail")
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button("DetailEdit") {}
                                }
                            }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(findButtonLabeled("HomeEdit", in: app.testing_rootElement) != nil)

        let go = try #require(findButtonLabeled("go", in: app.testing_rootElement))
        try await click(go, on: app)
        #expect(findButtonLabeled("DetailEdit", in: app.testing_rootElement) != nil)
        // Keep-alive home toolbar must not remain hit-testable / as bar primary.
        #expect(findButtonLabeled("HomeEdit", in: app.testing_rootElement) == nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func hiddenPageReleasesFirstResponder() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    VStack {
                        Button("rootBtn") {}
                        NavigationLink("go", value: 1)
                    }
                    .navigationDestination(for: Int.self) { _ in
                        Button("detailBtn") {}
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let rootBtn = try #require(findButtonLabeled("rootBtn", in: app.testing_rootElement))
        app.window.setFirstResponder(rootBtn)
        #expect(app.window.firstResponder === rootBtn)

        let go = try #require(findButtonLabeled("go", in: app.testing_rootElement))
        try await click(go, on: app)

        if let focused = app.window.firstResponder {
            #expect(!focused.isDescendant(of: rootBtn) && focused !== rootBtn)
        }
        #expect(findButtonLabeled("detailBtn", in: app.testing_rootElement) != nil)
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
