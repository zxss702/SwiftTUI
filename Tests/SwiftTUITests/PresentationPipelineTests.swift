import Testing
@testable import SwiftTUI

/// Behavioral: sheet/alert/popover Binding sync and live panel refresh.
@Suite(.serialized)
@MainActor
struct PresentationPipelineTests {

    @Test func sheetPresentDismissSyncsBinding() async throws {
        struct Root: View {
            @State var show = false
            var body: some View {
                VStack {
                    Text(show ? "open" : "closed")
                    Button("toggle") { show.toggle() }
                }
                .sheet(isPresented: $show) {
                    VStack {
                        Text("sheet-body")
                        Button("close") { show = false }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(findText(in: app.testing_rootElement, equalTo: "closed") != nil)

        let toggle = try #require(findButtonLabeled("toggle", in: app.testing_rootElement))
        try await click(toggle, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "sheet-body") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "open") != nil)

        let close = try #require(findButtonLabeled("close", in: app.testing_rootElement))
        try await click(close, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "sheet-body") == nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "closed") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func sheetContentRefreshesWhilePresented() async throws {
        struct Root: View {
            @State var show = false
            @State var label = "v1"
            var body: some View {
                Button("open") { show = true }
                    .sheet(isPresented: $show) {
                        VStack {
                            Text("sheet-\(label)")
                            Button("bump") { label = "v2" }
                        }
                    }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("open", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "sheet-v1") != nil)

        try await click(try #require(findButtonLabeled("bump", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "sheet-v2") != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func alertDismissesViaActionButton() async throws {
        struct Root: View {
            @State var show = false
            var body: some View {
                Button("ask") { show = true }
                    .alert("Title", isPresented: $show) {
                        Button("ok") {}
                    }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("ask", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "Title") != nil)

        try await click(try #require(findButtonLabeled("ok", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "Title") == nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func popoverPresentDismiss() async throws {
        struct Root: View {
            @State var show = false
            var body: some View {
                Button("pop") { show.toggle() }
                    .popover(isPresented: $show) {
                        Text("popover-body")
                    }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        try await click(try #require(findButtonLabeled("pop", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "popover-body") != nil)

        try await click(try #require(findButtonLabeled("pop", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "popover-body") == nil)
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
