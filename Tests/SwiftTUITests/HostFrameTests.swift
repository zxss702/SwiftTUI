import Testing
@testable import SwiftTUI

/// Headless host correctness: idle drain, input commit, no frame storms.
@Suite(.serialized)
@MainActor
struct HostFrameTests {

    // MARK: - Idle / storm

    @Test func simpleRootReachesIdle() async throws {
        let app = Application(rootView: Text("hello"))
        try await app.testing_prepare()
        #expect(!app.hasPendingCommitWork)
        let extra = try await app.testing_drainUntilIdle(maxCommits: 8)
        #expect(extra == 0)
        #expect(!app.hasPendingCommitWork)
    }

    @Test func navigationWithToolbarReachesIdle() async throws {
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
                            Button("Edit") {}
                        }
                    }
                    .navigationDestination(for: Int.self) { n in
                        Text("page \(n)")
                            .navigationTitle("P\(n)")
                            .toolbar {
                                ToolbarItem(placement: .navigation) {
                                    Button("★") {}
                                }
                            }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        let schedulesBefore = app.testing_scheduler.scheduleCallCount
        try await app.testing_prepare()
        #expect(!app.hasPendingCommitWork)

        // Further idle drains must not keep finding dirty work (toolbar loop).
        let extra = try await app.testing_drainUntilIdle(maxCommits: 16)
        #expect(extra == 0, "still dirty after prepare — toolbar/frame feedback loop")
        #expect(!app.hasPendingCommitWork)

        // A no-op turn must not enqueue an unbounded schedule storm.
        let before = app.testing_scheduler.scheduleCallCount
        try await app.testing_turn()
        let after = app.testing_scheduler.scheduleCallCount
        #expect(after - before <= 1)
        _ = schedulesBefore
    }

    @Test func scheduleCoalescesWhilePending() {
        let scheduler = FrameScheduler()
        scheduler.schedule()
        scheduler.schedule()
        scheduler.schedule()
        #expect(scheduler.scheduleCallCount == 3)
        #expect(scheduler.enqueuedWakeCount == 1)
        #expect(scheduler.hasPendingWake)
        scheduler.acknowledgeWake()
        #expect(!scheduler.hasPendingWake)
        scheduler.schedule()
        #expect(scheduler.enqueuedWakeCount == 2)
    }

    @Test func commitDoesNotEnqueueWakePerInvalidate() async throws {
        let app = Application(rootView: Text("x"))
        try await app.testing_prepare()
        app.testing_scheduler.testing_resetCounters()

        app.requestLayout()
        #expect(app.testing_scheduler.enqueuedWakeCount == 1)

        try await app.commitFrame()
        // During commit, Layer.invalidate must not enqueue additional wakes;
        // defer may schedule at most one residual.
        #expect(app.testing_scheduler.enqueuedWakeCount <= 2)
        try await app.testing_drainUntilIdle()
        #expect(!app.hasPendingCommitWork)
    }

    // MARK: - TextField input

    @Test func textFieldCommitsEveryKeystroke() async throws {
        final class Box: @unchecked Sendable {
            var text = ""
        }
        let box = Box()

        struct FieldView: View {
            let binding: Binding<String>
            var body: some View {
                TextField("type", text: binding)
            }
        }

        let binding = Binding(
            get: { box.text },
            set: { box.text = $0 }
        )
        let app = Application(rootView: FieldView(binding: binding))
        try await app.testing_prepare()

        let field = try #require(findTextField(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in ["a", "b", "c"] {
            let event = VTEvent.key(
                KeyEvent(character: Character(ch), keycode: 0, modifiers: [], type: .press)
            )
            try await app.testing_turn(input: event)
        }

        try await app.testing_drainUntilIdle()
        #expect(box.text == "abc", "got \(box.text.debugDescription) — keystrokes dropped or one-behind forever")
    }

    /// Paste arrives as per-character key events; spaces must not be dropped.
    @Test func textFieldPreservesSpaces() async throws {
        final class Box: @unchecked Sendable {
            var text = ""
        }
        let box = Box()

        struct FieldView: View {
            let binding: Binding<String>
            var body: some View {
                TextField("type", text: binding)
            }
        }

        let binding = Binding(
            get: { box.text },
            set: { box.text = $0 }
        )
        let app = Application(rootView: FieldView(binding: binding))
        try await app.testing_prepare()

        let field = try #require(findTextField(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for ch in "a b" {
            let event = VTEvent.key(
                KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press)
            )
            try await app.testing_turn(input: event)
        }

        try await app.testing_drainUntilIdle()
        #expect(box.text == "a b", "spaces dropped: \(box.text.debugDescription)")
    }

    /// Same paste-as-key-events path as TextField.
    @Test func textEditorPreservesSpaces() async throws {
        final class Box: @unchecked Sendable {
            var text = ""
        }
        let box = Box()

        struct EditorView: View {
            let binding: Binding<String>
            var body: some View {
                TextEditor(text: binding)
            }
        }

        let binding = Binding(
            get: { box.text },
            set: { box.text = $0 }
        )
        let app = Application(rootView: EditorView(binding: binding))
        try await app.testing_prepare()

        let editor = try #require(findTextEditor(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        for ch in "a b" {
            let event = VTEvent.key(
                KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press)
            )
            try await app.testing_turn(input: event)
        }

        try await app.testing_drainUntilIdle()
        #expect(box.text == "a b", "spaces dropped: \(box.text.debugDescription)")
    }

    @Test func stateToggleVisibleAfterOneCommit() async throws {
        let box = TapBox()
        let app = Application(rootView: TapView(onCount: { box.taps = $0 }))
        try await app.testing_prepare()
        #expect(box.taps == 0)

        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.taps == 1, "State not committed after click — got \(box.taps)")
        #expect(textLabel(in: button) == "+1", "label still +\(textLabel(in: button) ?? "?") — one-behind")
    }

    /// One-behind regression: after the click's commit(s), UI must already show
    /// the new state — a second interaction must not be required to "flush" it.
    @Test func clickDoesNotOneBehindLabel() async throws {
        let box = TapBox()
        let app = Application(rootView: TapView(onCount: { box.taps = $0 }))
        try await app.testing_prepare()

        let button = try #require(findButton(in: app.testing_rootElement))
        #expect(textLabel(in: button) == "+0")

        // Strict: at most one commit per mouse event (old input-loop shape).
        let pos = center(of: button)
        try await app.testing_turnSingleCommit(
            input: .mouse(MouseEvent(position: pos, type: .pressed(.left)))
        )
        try await app.testing_turnSingleCommit(
            input: .mouse(MouseEvent(position: pos, type: .released(.left)))
        )

        #expect(box.taps == 1)
        #expect(
            textLabel(in: button) == "+1",
            "after single-commit click, label=\(textLabel(in: button) ?? "nil") taps=\(box.taps) pending=\(app.hasPendingCommitWork) wake=\(app.testing_scheduler.hasPendingWake)"
        )
        #expect(
            !app.hasPendingCommitWork,
            "dirty left for next input/frame — next click would paint this action"
        )
    }

    @Test func consecutiveClicksEachVisibleBeforeNext() async throws {
        let box = TapBox()
        let app = Application(rootView: TapView(onCount: { box.taps = $0 }))
        try await app.testing_prepare()

        let button = try #require(findButton(in: app.testing_rootElement))
        for expected in 1...5 {
            try await click(button, on: app)
            #expect(box.taps == expected, "tap \(expected): state=\(box.taps)")
            #expect(
                textLabel(in: button) == "+\(expected)",
                "tap \(expected): label=\(textLabel(in: button) ?? "nil") (one-behind)"
            )
            #expect(!app.hasPendingCommitWork)
        }
    }

    /// Product rule: Buttons are pointer-activated, never keyboard firstResponder
    /// (only TextField/SecureField/TextEditor take focus + caret).
    @Test func buttonNeverBecomesFirstResponder() async throws {
        let box = TapBox()
        let app = Application(rootView: TapView(onCount: { box.taps = $0 }))
        try await app.testing_prepare()

        let button = try #require(findButton(in: app.testing_rootElement))
        app.window.setFirstResponder(button)
        #expect(app.window.firstResponder == nil, "Button must not take keyboard focus")

        try await app.testing_turn(
            input: .key(KeyEvent(character: " ", keycode: 0, modifiers: [], type: .press))
        )
        #expect(box.taps == 0, "space must not activate an unfocused Button")
    }

    /// `onAppear` must apply in the same host settle as first layout — not on a
    /// later `DispatchQueue.main.async` turn (classic one-behind for titles).
    @Test func onDisappearAppliesWhenRemoved() async throws {
        final class Box { var gone = false }
        let box = Box()

        struct Host: View {
            @State var show = true
            let onGone: () -> Void
            var body: some View {
                VStack {
                    if show {
                        Text("leaf")
                            .onDisappear(onGone)
                    }
                    Button("hide") { show = false }
                }
            }
        }

        let app = Application(rootView: Host(onGone: { box.gone = true }))
        try await app.testing_prepare()
        #expect(!box.gone)

        let button = try #require(findButton(in: app.testing_rootElement))
        try await click(button, on: app)
        #expect(box.gone, "onDisappear must run in the same settle as removal")
        #expect(!app.hasPendingCommitWork)
    }

    @Test func onAppearAppliesInSamePrepareTurn() async throws {
        final class Box: @unchecked Sendable {
            var flag = false
        }
        let box = Box()

        struct AppearView: View {
            let box: Box
            @State var label = "before"
            var body: some View {
                Text(label)
                    .onAppear {
                        box.flag = true
                        label = "after"
                    }
            }
        }

        let app = Application(rootView: AppearView(box: box))
        try await app.testing_prepare()

        #expect(box.flag, "onAppear still deferred — will paint on next interaction")
        #expect(
            findText(in: app.testing_rootElement, equalTo: "after") != nil,
            "label still 'before' after prepare — one-behind"
        )
        #expect(!app.hasPendingCommitWork)
    }

    @Test func navigationTitleVisibleAfterPrepare() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    Text("body")
                        .navigationTitle("HomeTitle")
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(
            findText(in: app.testing_rootElement, equalTo: "HomeTitle") != nil,
            "navigationTitle from onAppear missing after prepare — one-behind chrome"
        )
        #expect(!app.hasPendingCommitWork)
    }

    @Test func toolbarTitleMenuVisibleAfterPrepare() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    Text("body")
                        .navigationTitle("MenuTitle")
                        .toolbarTitleMenu {
                            Button("MenuAction") {}
                        }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        #expect(
            findButtonLabeled("MenuTitle", in: app.testing_rootElement) != nil,
            "toolbarTitleMenu title trigger missing after prepare"
        )
        #expect(!app.hasPendingCommitWork)
    }

    // MARK: - Mouse-move flood (DECSET 1003)

    @Test func hostEventPolicySkipsSettleOnMove() {
        let move = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .move))
        let scroll = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .scroll(deltaX: 0, deltaY: 1)))
        let click = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .pressed(.left)))
        let key = VTEvent.key(KeyEvent(character: "a", keycode: 0, modifiers: [], type: .press))
        #expect(!HostEventPolicy.shouldWakeFrameLoop(move))
        #expect(HostEventPolicy.shouldWakeFrameLoop(scroll))
        #expect(HostEventPolicy.shouldWakeFrameLoop(click))
        #expect(HostEventPolicy.shouldWakeFrameLoop(key))
    }

    /// Settling every hover enter/leave burns commits — why move must not inline-settle.
    /// Uses `Button(hover:)` + `@State` (default Button no longer paints on hover).
    @Test func alwaysSettlingHoverToggleBurnsCommits() async throws {
        struct HoverBurn: View {
            @State var ticks = 0
            var body: some View {
                Button("hover-target", hover: { ticks += 1 }) {}
            }
        }
        let app = Application(rootView: HoverBurn())
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))
        let inside = center(of: button)
        let outside = Position(column: 0, line: Extended(20))

        var commits = 0
        for i in 0 ..< 40 {
            let pos = i.isMultiple(of: 2) ? inside : outside
            commits += try await app.testing_turnAlwaysSettle(
                input: .mouse(MouseEvent(position: pos, type: .move))
            )
        }
        #expect(commits >= 10, "expected hover toggles to settle; got \(commits)")
    }

    /// After a 1003-style move storm, click must still land (production dispatch).
    @Test func mouseMoveStormDoesNotStarveClick() async throws {
        let box = TapBox()
        let app = Application(rootView: TapView(onCount: { box.taps = $0 }))
        try await app.testing_prepare()
        let button = try #require(findButton(in: app.testing_rootElement))

        for i in 0 ..< 300 {
            let pos = Position(column: Extended(i % 40), line: Extended((i / 40) % 10))
            try await app.testing_turn(
                input: .mouse(MouseEvent(position: pos, type: .move))
            )
        }

        try await click(button, on: app)
        #expect(box.taps == 1, "click starved after move storm — taps=\(box.taps)")
        #expect(textLabel(in: button) == "+1")
    }

    /// Keys must not sit forever behind hover settles.
    @Test func mouseMoveStormDoesNotStarveKey() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct FieldView: View {
            let binding: Binding<String>
            var body: some View { TextField("t", text: binding) }
        }
        let app = Application(
            rootView: FieldView(
                binding: Binding(get: { box.text }, set: { box.text = $0 })
            )
        )
        try await app.testing_prepare()
        let field = try #require(findTextField(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        for i in 0 ..< 300 {
            try await app.testing_turn(
                input: .mouse(MouseEvent(
                    position: Position(column: Extended(i % 30), line: 0),
                    type: .move
                ))
            )
        }

        try await app.testing_turn(
            input: .key(KeyEvent(character: "z", keycode: 0, modifiers: [], type: .press))
        )
        #expect(box.text == "z", "key starved after move storm — text=\(box.text.debugDescription)")
    }

    @Test func scrollWakesFrameLoop() async throws {
        #expect(
            HostEventPolicy.shouldWakeFrameLoop(
                .mouse(MouseEvent(position: Position(x: 0, y: 0), type: .scroll(deltaX: 0, deltaY: 1)))
            )
        )
    }

    @Test func textFieldNotOneBehindAcrossKeys() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()
        struct FieldView: View {
            let binding: Binding<String>
            var body: some View { TextField("t", text: binding) }
        }
        let app = Application(
            rootView: FieldView(
                binding: Binding(get: { box.text }, set: { box.text = $0 })
            )
        )
        try await app.testing_prepare()
        let field = try #require(findTextField(in: app.testing_rootElement))
        app.window.setFirstResponder(field)
        try await app.testing_turn()

        var expected = ""
        for ch in ["x", "y", "z"] {
            expected.append(ch)
            try await app.testing_turn(
                input: .key(KeyEvent(character: Character(ch), keycode: 0, modifiers: [], type: .press))
            )
            #expect(
                box.text == expected,
                "after '\(ch)' binding=\(box.text.debugDescription) expected=\(expected.debugDescription)"
            )
            #expect(!app.hasPendingCommitWork)
        }
    }
}

// MARK: - Fixtures

@MainActor
private final class TapBox: @unchecked Sendable {
    var taps = 0
}

@MainActor
private struct TapView: View {
    @State var count = 0
    let onCount: (Int) -> Void
    var body: some View {
        let _ = onCount(count)
        Button("+\(count)") { count += 1 }
    }
}

// MARK: - Tree helpers

@MainActor
private func findTextField(in control: Element?) -> Element? {
    guard let control else { return nil }
    if control is TextFieldElement { return control }
    for child in control.children {
        if let found = findTextField(in: child) { return found }
    }
    return nil
}

@MainActor
private func findTextEditor(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("TextEditorElement") {
        return control
    }
    for child in control.children {
        if let found = findTextEditor(in: child) { return found }
    }
    return nil
}

@MainActor
private func findButton(in control: Element?) -> Element? {
    guard let control else { return nil }
    let name = String(describing: type(of: control))
    if name.contains("Button") { return control }
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
private func center(of control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
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
private func click(_ button: Element, on app: Application) async throws {
    app.window.setFirstResponder(button)
    let pos = center(of: button)
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .pressed(.left)))
    )
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .released(.left)))
    )
}
