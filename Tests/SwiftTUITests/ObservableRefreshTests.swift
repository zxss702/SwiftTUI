import Observation
import Testing
@testable import SwiftTUI

/// Regression: `@Observable` mutations must refresh composed views without resize.
@Suite(.serialized)
@MainActor
struct ObservableRefreshTests {
    @Observable
    final class Session {
        var info = "v4-flash"
    }

    @Test func pickerLabelRefreshesWhenObservableBindingChanges() async throws {
        let session = Session()

        struct Row: View {
            @Bindable var session: Session
            var body: some View {
                Picker("", selection: Binding(
                    get: { session.info },
                    set: { session.info = $0 }
                )) {
                    Text("v4-flash").tag("v4-flash")
                    Text("v4-pro").tag("v4-pro")
                }
                .labelsHidden()
            }
        }

        struct Root: View {
            let session: Session
            var body: some View {
                Row(session: session)
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        session.info = "v4-pro"
        try await app.testing_drainUntilIdle()

        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") == nil)
    }

    @Test func stateHeldObservableRefreshesLabel() async throws {
        final class Box: @unchecked Sendable {
            var session: Session?
        }
        let box = Box()

        struct Root: View {
            @State var session = Session()
            let box: Box
            var body: some View {
                let _ = { box.session = session }()
                VStack {
                    Text(session.info)
                    Button("flip") { session.info = "v4-pro" }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        let session = try #require(box.session)
        session.info = "v4-pro"
        try await app.testing_drainUntilIdle()

        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
    }

    @Test func lazyStackRowRefreshesObservableLabel() async throws {
        let session = Session()

        struct Root: View {
            let session: Session
            var body: some View {
                ScrollView {
                    LazyVStack {
                        Text(session.info)
                        Text("anchor")
                    }
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        session.info = "v4-pro"
        try await app.testing_drainUntilIdle()

        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
    }

    /// SettingView shape: NavigationStack + LazyVStack + menu-style Picker Binding
    /// into `@Observable` session — selecting a menu item must refresh the label.
    @Test func menuPickerSelectionRefreshesObservableLabel() async throws {
        let session = Session()

        struct Row: View {
            @Bindable var session: Session
            var body: some View {
                HStack {
                    Text("梦想家")
                    Picker("", selection: Binding(
                        get: { session.info },
                        set: { session.info = $0 }
                    )) {
                        Text("v4-flash").tag("v4-flash")
                        Text("v4-pro").tag("v4-pro")
                    }
                    .labelsHidden()
                }
            }
        }

        struct Root: View {
            let session: Session
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVStack {
                            Row(session: session)
                        }
                    }
                    .navigationTitle("设置")
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 50, height: 16))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        // Open menu-style Picker (label shows current selection + ▾).
        let trigger = try #require(findButtonContaining(in: app.testing_rootElement, text: "v4-flash"))
        try await click(trigger, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        let pro = try #require(findButtonLabeled("v4-pro", in: app.testing_rootElement))
        try await click(pro, on: app)
        try await app.testing_drainUntilIdle()

        #expect(session.info == "v4-pro")
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
        #expect(
            findText(in: app.testing_rootElement, equalTo: "v4-flash") == nil,
            "menu Picker label must refresh after Observable Binding set"
        )
    }

    /// Exact SettingView pattern: `@State` holds `@Observable` session; row takes
    /// `Binding` from `session.binding`-style closures; many rows in LazyVStack.
    @Test func stateSessionBindingRowsRefreshAfterMenuPick() async throws {
        final class Box: @unchecked Sendable {
            var session: Session?
        }
        let box = Box()

        struct ModelRow: View {
            let title: String
            let modelNames: [String]
            @Binding var selection: String
            var body: some View {
                HStack {
                    Text(title)
                    Picker("", selection: $selection) {
                        if selection.isEmpty || !modelNames.contains(selection) {
                            Text(selection.isEmpty ? "-" : selection).tag(selection)
                        }
                        ForEach(modelNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                }
            }
        }

        struct Settings: View {
            @State var session = Session()
            let box: Box
            var binding: Binding<String> {
                Binding(get: { session.info }, set: { session.info = $0 })
            }
            var body: some View {
                let _ = { box.session = session }()
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ModelRow(
                                title: "梦想家",
                                modelNames: ["v4-flash", "v4-pro", "v4-flash T"],
                                selection: binding
                            )
                            Divider()
                            ModelRow(
                                title: "实干家",
                                modelNames: ["v4-flash", "v4-pro", "v4-flash T"],
                                selection: binding
                            )
                        }
                    }
                    .navigationTitle("设置")
                }
            }
        }

        let app = Application(rootView: Settings(box: box))
        try await app.testing_prepare(size: Size(width: 60, height: 20))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        let trigger = try #require(findButtonContaining(in: app.testing_rootElement, text: "v4-flash"))
        try await click(trigger, on: app)
        let pro = try #require(findButtonLabeled("v4-pro", in: app.testing_rootElement))
        try await click(pro, on: app)
        try await app.testing_drainUntilIdle()

        #expect(box.session?.info == "v4-pro")
        // Both rows share the binding — labels must show the new value.
        let proLabels = countText(in: app.testing_rootElement, equalTo: "v4-pro")
        #expect(proLabels >= 1, "expected refreshed Picker label(s), found \(proLabels)")
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") == nil)
    }

    /// Observable reads that only happen inside `ScrollViewReader` / `GeometryReader`
    /// content closures must still invalidate (dialogue `@Query` + side panel shape).
    @Test func observableReadInsideScrollViewReaderRefreshes() async throws {
        let session = Session()

        struct Root: View {
            let session: Session
            var body: some View {
                ScrollViewReader { _ in
                    ScrollView {
                        Text(session.info)
                    }
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        session.info = "v4-pro"
        try await app.testing_drainUntilIdle()

        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") == nil)
    }

    @Test func observableReadInsideGeometryReaderRefreshes() async throws {
        let session = Session()

        struct Root: View {
            let session: Session
            var body: some View {
                GeometryReader { _ in
                    Text(session.info)
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "v4-flash") != nil)

        session.info = "v4-pro"
        try await app.testing_drainUntilIdle()

        #expect(findText(in: app.testing_rootElement, equalTo: "v4-pro") != nil)
    }

    /// Picker label string length change must resize the trigger (not wait for window resize).
    @Test func menuPickerLabelWidthTracksSelectionLength() async throws {
        let session = Session()
        session.info = "ab"

        struct Root: View {
            @Bindable var session: Session
            var body: some View {
                HStack {
                    Text("left").frame(maxWidth: .infinity, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { session.info },
                        set: { session.info = $0 }
                    )) {
                        Text("ab").tag("ab")
                        Text("abcdefghij").tag("abcdefghij")
                    }
                    .labelsHidden()
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 40, height: 6))

        let shortTrigger = try #require(findButtonContaining(in: app.testing_rootElement, text: "ab"))
        let shortWidth = shortTrigger.absoluteFrame.size.width

        session.info = "abcdefghij"
        try await app.testing_drainUntilIdle()

        let longTrigger = try #require(findButtonContaining(in: app.testing_rootElement, text: "abcdefghij"))
        let longWidth = longTrigger.absoluteFrame.size.width
        #expect(longWidth > shortWidth, "longer label must widen trigger (\(longWidth) vs \(shortWidth))")

        session.info = "ab"
        try await app.testing_drainUntilIdle()

        let back = try #require(findButtonContaining(in: app.testing_rootElement, text: "ab"))
        #expect(
            back.absoluteFrame.size.width < longWidth,
            "shorter label must shrink trigger again"
        )
    }

    /// Same display width under LazyVStack: model `text` must paint new glyphs
    /// without a window resize (LazyVStack skips layout when size is unchanged).
    @Test func menuPickerSameWidthLabelPaintsWithoutResize() async throws {
        let session = Session()
        session.info = "aaaa"

        struct Root: View {
            @Bindable var session: Session
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            HStack {
                                Text("梦想家")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Picker("", selection: Binding(
                                    get: { session.info },
                                    set: { session.info = $0 }
                                )) {
                                    Text("aaaa").tag("aaaa")
                                    Text("bbbb").tag("bbbb")
                                }
                                .labelsHidden()
                            }
                        }
                    }
                    .navigationTitle("设置")
                }
            }
        }

        let app = Application(rootView: Root(session: session))
        try await app.testing_prepare(size: Size(width: 50, height: 12))

        let before = try #require(findButtonContaining(in: app.testing_rootElement, text: "aaaa"))
        let beforeWidth = before.absoluteFrame.size.width
        #expect(paintedWindow(app).contains("aaaa"))

        // Menu pick (same path as Settings) — equal display width.
        try await click(before, on: app)
        let option = try #require(findButtonLabeled("bbbb", in: app.testing_rootElement))
        try await click(option, on: app)
        try await app.testing_drainUntilIdle()

        #expect(session.info == "bbbb")
        let after = try #require(findButtonContaining(in: app.testing_rootElement, text: "bbbb"))
        #expect(
            after.absoluteFrame.size.width == beforeWidth,
            "same-width labels must keep trigger width (covers LazyVStack skip-layout)"
        )

        let screen = paintedWindow(app)
        #expect(screen.contains("bbbb"), "framebuffer must show new label without resize")
        #expect(!screen.contains("aaaa"), "framebuffer must not keep stale picker glyphs")
    }
}

@MainActor
private func paintedWindow(_ app: Application) -> String {
    var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
    app.window.layer.draw(into: &buffer)
    let size = app.window.layer.frame.size
    var rows: [String] = []
    for line in 0 ..< size.height.intValue {
        var row = ""
        for col in 0 ..< size.width.intValue {
            row.append(buffer.character(at: Position(column: Extended(col), line: Extended(line))) ?? " ")
        }
        rows.append(row)
    }
    return rows.joined(separator: "\n")
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

@MainActor
private func countText(in control: Element?, equalTo value: String) -> Int {
    guard let control else { return 0 }
    var count = 0
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String,
       text == value
    {
        count += 1
    }
    for child in control.children {
        count += countText(in: child, equalTo: value)
    }
    return count
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
    if String(describing: type(of: root)).contains("Button"),
       textLabel(in: root) == label
    {
        return root
    }
    for child in root.children {
        if let found = findButtonLabeled(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func findButtonContaining(in root: Element?, text: String) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"),
       (textLabel(in: root) ?? "").contains(text)
    {
        return root
    }
    for child in root.children {
        if let found = findButtonContaining(in: child, text: text) { return found }
    }
    return nil
}

@MainActor
private func click(_ element: Element, on app: Application) async throws {
    let frame = element.absoluteFrame
    let pos = Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .pressed(.left)))
    )
    try await app.testing_turn(
        input: .mouse(MouseEvent(position: pos, type: .released(.left)))
    )
}
