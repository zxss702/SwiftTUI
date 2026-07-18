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

    @Test func toolbarTitleMenuTurnsTitleIntoMenu() async throws {
        final class Box { var taps = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                NavigationStack {
                    Text("body")
                        .navigationTitle("HomeTitle")
                        .toolbarTitleMenu {
                            Button("RenameAction") { box.taps += 1 }
                        }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        #expect(findText(in: app.testing_rootElement, equalTo: "HomeTitle") != nil)
        #expect(findButtonLabeled("RenameAction", in: app.testing_rootElement) == nil)

        let title = try #require(findButtonLabeled("HomeTitle", in: app.testing_rootElement))
        try await click(title, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        let action = try #require(findButtonLabeled("RenameAction", in: app.testing_rootElement))
        try await click(action, on: app)
        #expect(box.taps == 1)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func toolbarTitleMenuClearsOnPushAndRestoresOnPop() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("home")
                        NavigationLink("go", value: 1)
                    }
                    .navigationTitle("Home")
                    .toolbarTitleMenu {
                        Button("HomeMenuItem") {}
                    }
                    .navigationDestination(for: Int.self) { _ in
                        Text("detail")
                            .navigationTitle("Detail")
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(findButtonLabeled("Home", in: app.testing_rootElement) != nil)

        try await click(try #require(findButtonLabeled("go", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "Detail") != nil)
        // Detail has no title menu — plain title text, not a menu trigger.
        #expect(findButtonLabeled("Home", in: app.testing_rootElement) == nil)
        #expect(findButtonLabeled("Detail", in: app.testing_rootElement) == nil)

        let back = try #require(findButtonLabeled("⟨Home", in: app.testing_rootElement)
            ?? findButtonLabeled("⟨返回", in: app.testing_rootElement))
        try await click(back, on: app)
        #expect(findButtonLabeled("Home", in: app.testing_rootElement) != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func toolbarTitleMenuViaToolbarContent() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    Text("body")
                        .navigationTitle("ViaToolbar")
                        .toolbar {
                            ToolbarTitleMenu {
                                Button("ViaMenuItem") {}
                            }
                        }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let title = try #require(findButtonLabeled("ViaToolbar", in: app.testing_rootElement))
        try await click(title, on: app)
        #expect(findButtonLabeled("ViaMenuItem", in: app.testing_rootElement) != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func principalOverridesToolbarTitleMenu() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    Text("body")
                        .navigationTitle("HiddenTitle")
                        .toolbarTitleMenu {
                            Button("ShouldNotOpen") {}
                        }
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("PrincipalLabel")
                            }
                        }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(findText(in: app.testing_rootElement, equalTo: "PrincipalLabel") != nil)
        #expect(findButtonLabeled("HiddenTitle", in: app.testing_rootElement) == nil)
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
        // Buttons are not first-responders; setFirstResponder must reject them.
        app.window.setFirstResponder(rootBtn)
        #expect(app.window.firstResponder == nil)

        let go = try #require(findButtonLabeled("go", in: app.testing_rootElement))
        try await click(go, on: app)

        #expect(findButtonLabeled("detailBtn", in: app.testing_rootElement) != nil)
        #expect(!app.hasPendingCommitWork)
    }

    /// Regression: ForEach used to skip updates when path values were unchanged,
    /// so `.hidden(stack.last != value)` never flipped — middle keep-alive pages
    /// kept painting over the top destination (Settings → 管理模型 → 编辑).
    @Test func nestedPushHidesMiddleKeepAlivePage() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("rootUniqueMarker")
                        NavigationLink("toMid", value: 1)
                    }
                    .navigationDestination(for: Int.self) { n in
                        VStack {
                            Text("page-\(n)")
                            if n == 1 {
                                NavigationLink("toLeaf", value: 2)
                            }
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()

        try await click(try #require(findButtonLabeled("toMid", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "page-1") != nil)

        let toLeaf = try #require(findButtonLabeled("toLeaf", in: app.testing_rootElement))
        try await click(toLeaf, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "page-2") != nil)

        // Keep-alive mid page still mounts `toLeaf`, but hit-testing must miss it.
        let midLink = try #require(findButtonLabeled("toLeaf", in: app.testing_rootElement))
        let hit = app.testing_rootElement.hitTest(position: center(of: midLink))
        #expect(hit !== midLink)
        #expect(!app.hasPendingCommitWork)
    }

    /// Settings → 管理模型 → 编辑：双层 push 后 ScrollView 内 bordered TextField
    /// 必须能点击获得 firstResponder 并接收按键。
    @Test func nestedPushScrollViewTextFieldAcceptsTyping() async throws {
        final class Box { var name = "" }
        let box = Box()
        struct Root: View {
            let binding: Binding<String>
            var body: some View {
                NavigationStack {
                    VStack {
                        Text("settings-root")
                        NavigationLink("manage", value: 1)
                    }
                    .navigationDestination(for: Int.self) { n in
                        if n == 1 {
                            VStack {
                                Text("model-list")
                                NavigationLink("edit", value: 2)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("edit-form")
                                    HStack {
                                        Text("名称")
                                            .bold()
                                            .frame(width: 8)
                                        TextField("placeholder", text: binding)
                                            .labelsHidden()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .border(style: .rounded)
                                    }
                                }
                                .padding(1)
                            }
                        }
                    }
                }
            }
        }

        let binding = Binding(
            get: { box.name },
            set: { box.name = $0 }
        )
        let app = Application(rootView: Root(binding: binding))
        try await app.testing_prepare(size: Size(width: 60, height: 20))

        try await click(try #require(findButtonLabeled("manage", in: app.testing_rootElement)), on: app)
        try await click(try #require(findButtonLabeled("edit", in: app.testing_rootElement)), on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "edit-form") != nil)

        let field = try #require(findTextField(in: app.testing_rootElement))
        #expect(field.absoluteFrame.size.width > 0, "TextField must have non-zero frame")

        let pos = center(of: field)
        // Do not force setFirstResponder — click path must win focus.
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(
            app.window.firstResponder === field,
            "click must focus TextField (got \(String(describing: app.window.firstResponder.map { type(of: $0) })))"
        )

        for ch in ["A", "B"] {
            try await app.testing_turn(
                input: .key(KeyEvent(character: Character(ch), keycode: 0, modifiers: [], type: .press))
            )
        }
        #expect(box.name == "AB", "typed text must reach Binding (got \(box.name))")
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
private func findTextField(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("TextField") { return control }
    for child in control.children {
        if let found = findTextField(in: child) { return found }
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
