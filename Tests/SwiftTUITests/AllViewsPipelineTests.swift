import Testing
@testable import SwiftTUI

/// Smoke: every public View / modifier builds, prepares, and reaches idle on the new host.
@Suite(.serialized)
@MainActor
struct AllViewsPipelineTests {

    private func assertIdle<V: View>(_ root: V) async throws {
        let app = Application(rootView: root)
        try await app.testing_prepare()
        #expect(!app.hasPendingCommitWork)
        let extra = try await app.testing_drainUntilIdle(maxCommits: 8)
        #expect(extra == 0, "leftover dirty after prepare for \(V.self)")
    }

    // MARK: - Structural

    @Test func emptyView() async throws { try await assertIdle(EmptyView()) }
    @Test func group() async throws { try await assertIdle(Group { Text("g") }) }
    @Test func anyView() async throws { try await assertIdle(AnyView(Text("a"))) }
    @Test func optionalSome() async throws {
        let v: Text? = Text("x")
        try await assertIdle(v)
    }
    @Test func optionalNone() async throws {
        let v: Text? = nil
        try await assertIdle(v)
    }
    @Test func forEach() async throws {
        try await assertIdle(ForEach(0 ..< 3, id: \.self) { Text("\($0)") })
    }
    @Test func section() async throws {
        try await assertIdle(Section { Text("body") } header: { Text("h") })
    }
    @Test func conditionalTrue() async throws {
        try await assertIdle(Group {
            if true { Text("t") } else { Text("f") }
        })
    }

    // MARK: - Stacks / layout

    @Test func vstack() async throws { try await assertIdle(VStack { Text("a"); Text("b") }) }
    @Test func hstack() async throws { try await assertIdle(HStack { Text("a"); Text("b") }) }
    @Test func zstack() async throws { try await assertIdle(ZStack { Text("a"); Text("b") }) }
    @Test func lazyVStack() async throws {
        try await assertIdle(LazyVStack { ForEach(0 ..< 5, id: \.self) { Text("\($0)") } })
    }
    @Test func lazyVGrid() async throws {
        try await assertIdle(LazyVGrid(columns: [GridItem(.flexible())]) {
            ForEach(0 ..< 4, id: \.self) { Text("\($0)") }
        })
    }
    @Test func scrollView() async throws {
        try await assertIdle(ScrollView { VStack { Text("1"); Text("2") } })
    }
    @Test func geometryReader() async throws {
        try await assertIdle(GeometryReader { size in Text("\(size.width)") })
    }
    @Test func spacerDividerColor() async throws {
        try await assertIdle(VStack {
            Spacer()
            Divider()
            Color.red
        })
    }

    // MARK: - Controls

    @Test func textButton() async throws {
        try await assertIdle(VStack {
            Text("hi").bold().italic().underline().strikethrough()
            Button("go") {}
        })
    }
    @Test func textFieldSecure() async throws {
        try await assertIdle(VStack {
            TextField("p", text: .constant(""))
            SecureField("s", text: .constant(""))
        })
    }
    @Test func textEditor() async throws {
        try await assertIdle(TextEditor(text: .constant("hello")))
    }
    @Test func toggleSliderStepperProgress() async throws {
        try await assertIdle(VStack {
            Toggle(isOn: .constant(true)) { Text("t") }
            Slider(value: .constant(0.5))
            Stepper(value: .constant(1), in: 0 ... 10) { Text("s") }
            ProgressView()
            ProgressView(value: 0.3)
        })
    }
    @Test func pickerMenu() async throws {
        try await assertIdle(VStack {
            Picker("p", selection: .constant(1)) {
                Text("one").tag(1)
                Text("two").tag(2)
            }
            Menu("m") { Button("a") {} }
        })
    }

    // MARK: - Modifiers (layout / chrome)

    @Test func layoutModifiers() async throws {
        try await assertIdle(
            Text("x")
                .padding()
                .frame(width: 10, height: 1)
                .frame(maxWidth: .infinity)
                .fixedSize()
                .layoutPriority(1)
                .border()
                .background(.blue)
                .overlay { Text("o") }
                .hidden(false)
                .disabled(false)
                .allowsHitTesting(true)
        )
    }

    @Test func textEnvModifiers() async throws {
        try await assertIdle(
            Text("x")
                .foregroundColor(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        )
    }

    @Test func interactionModifiers() async throws {
        try await assertIdle(
            Text("x")
                .onAppear {}
                .onDisappear {}
                .onChange(of: 1) { _, _ in }
                .onHover { _ in }
                .onTapGesture {}
                .gesture(DragGesture().onChanged { _ in }.onEnded { _ in })
                .task {}
        )
    }

    @Test func focusModifiers() async throws {
        struct Root: View {
            @FocusState var focused: Bool
            @State var text = ""
            var body: some View {
                TextField("f", text: $text)
                    .focused($focused)
                    .focusable(true)
                    .defaultFocus($focused, true)
            }
        }
        try await assertIdle(Root())
    }

    @Test func environmentTagVisibility() async throws {
        try await assertIdle(
            Text("x")
                .environment(\.foregroundColor, .green)
                .tag(1)
                .labelsHidden()
        )
    }

    @Test func equatableModifier() async throws {
        struct EqText: View, Equatable {
            var body: some View { Text("x") }
        }
        try await assertIdle(EqText().equatable())
    }

    @Test func scrollViewReader() async throws {
        try await assertIdle(
            ScrollViewReader { proxy in
                ScrollView {
                    Text("row").id("r")
                }
                .onAppear { proxy.scrollTo("r") }
            }
        )
    }

    // MARK: - Navigation / presentation

    @Test func navigationStack() async throws {
        try await assertIdle(
            NavigationStack {
                Text("home")
                    .navigationTitle("Home")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { Button("E") {} }
                    }
                    .navigationDestination(for: Int.self) { n in
                        Text("\(n)")
                    }
            }
        )
    }

    @Test func navigationLink() async throws {
        try await assertIdle(
            NavigationStack {
                NavigationLink("go", value: 1)
                    .navigationDestination(for: Int.self) { Text("\($0)") }
            }
        )
    }

    @Test func sheetPopoverAlert() async throws {
        try await assertIdle(
            Text("root")
                .sheet(isPresented: .constant(false)) { Text("sheet") }
                .popover(isPresented: .constant(false)) { Text("pop") }
                .alert("a", isPresented: .constant(false)) { Button("ok") {} }
                .confirmationDialog("c", isPresented: .constant(false)) { Button("ok") {} }
        )
    }

    // MARK: - Behavioral (update paths)

    @Test func buttonLabelResyncsOnStateChange() async throws {
        final class Box { var label = "" }
        let box = Box()
        struct Root: View {
            @State var n = 0
            let report: (String) -> Void
            var body: some View {
                let title = "n=\(n)"
                let _ = report(title)
                Button(title) { n += 1 }
            }
        }
        let app = Application(rootView: Root(report: { box.label = $0 }))
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.label == "n=1")
        #expect(!app.hasPendingCommitWork)
    }

    @Test func onHoverActionUpdatesOnRerender() async throws {
        final class Box { var last: Bool?; var renders = 0 }
        let box = Box()
        struct Root: View {
            @State var tick = 0
            let box: Box
            var body: some View {
                let _ = { box.renders += 1 }()
                Text("h\(tick)")
                    .onHover { box.last = $0 }
                Button("t") { tick += 1 }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.renders >= 2)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func geometryReaderBranchSwitchSettles() async throws {
        try await assertIdle(
            GeometryReader { size in
                if size.width > 10 {
                    Text("wide")
                } else {
                    Text("narrow")
                }
            }
        )
    }

    @Test func stackReconcilesSameIndexIdentitySwap() async throws {
        struct Root: View {
            @State var showButton = false
            var body: some View {
                VStack {
                    if showButton {
                        Button("inner") {}
                    } else {
                        Text("plain")
                    }
                    Button("flip") { showButton = true }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let flip = try #require(findButton(in: app.testing_rootElement))
        try await click(flip, on: app)
        #expect(findButton(in: app.testing_rootElement) != nil)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func pickerMenuLabelResyncs() async throws {
        struct Root: View {
            @State var selection = 1
            var body: some View {
                VStack {
                    Picker("p", selection: $selection) {
                        Text("one").tag(1)
                        Text("two").tag(2)
                    }
                    Button("sel2") { selection = 2 }
                }
            }
        }
        let app = Application(rootView: Root())
        try await app.testing_prepare()
        let button = try #require(findButtonLabeled("sel2", in: app.testing_rootElement))
        try await click(button, on: app)
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
