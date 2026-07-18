import Testing
@testable import SwiftTUI

/// Runtime probes for presentation hover isolation, TextField focus, and nav paint dirty.
@Suite(.serialized)
@MainActor
struct InteractionIsolationTests {

    /// Paired press+release activates once on gesture ended (UIKit touchUpInside).
    /// Orphan release alone must NOT activate.
    @Test func orphanReleaseActivatesButtonOnce() async throws {
        final class Box { var taps = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Button("act") { box.taps += 1 }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        let button = try #require(findButtonLabeled("act", in: app.testing_rootElement))
        let pos = center(of: button)

        // Release only — no session → ignored.
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.taps == 0, "orphan release must not activate (taps=\(box.taps))")

        // Real press+release fires once on ended.
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.taps == 1, "paired press+release must fire once (taps=\(box.taps))")
    }

    /// Terminal release coords often drift 1–3 cells; fire if tracking.
    @Test func buttonFiresWhenReleaseDriftsOutsideFrame() async throws {
        final class Box { var taps = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Button("drift") { box.taps += 1 }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        let button = try #require(findButtonLabeled("drift", in: app.testing_rootElement))
        let inside = center(of: button)
        let frame = button.absoluteFrame
        let drifted = Position(
            column: frame.position.column + frame.size.width + 2,
            line: frame.position.line
        )
        #expect(!frame.contains(drifted))

        try await app.testing_turn(input: .mouse(MouseEvent(position: inside, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: drifted, type: .released(.left))))
        #expect(box.taps == 1, "tracking button must fire despite release drift (taps=\(box.taps))")
    }

    /// Outer `.padding` on a Button must not hit-test as the Button.
    @Test func outerPaddingDoesNotClickWrappedButton() async throws {
        final class Box { var count = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Button("padBtn") { box.count += 1 }
                    .padding(2)
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 12))

        let button = try #require(findButtonLabeled("padBtn", in: app.testing_rootElement))
        // Corner of the padded wrapper — outside the Button's own frame.
        let padPos = button.absoluteFrame.position - Position(column: 1, line: 1)
        try await app.testing_turn(input: .mouse(MouseEvent(position: padPos, type: .pressed(.left))))
        #expect(box.count == 0, "outer padding must not activate Button (got \(box.count))")
    }

    /// Menu item clicks must hit the item Button — not the overlay ZStack
    /// (regression: ZStack absorbed misses → pointer nil → dead clicks).
    @Test func menuItemClickActivatesWhileOpen() async throws {
        final class Box { var taps = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Menu("menu") {
                    Button("item") { box.taps += 1 }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let menu = try #require(findButtonLabeled("menu", in: app.testing_rootElement))
        try await clickAt(center(of: menu), on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        let item = try #require(findButtonLabeled("item", in: app.testing_rootElement))
        let itemPos = center(of: item)
        let panel = app.window.popupPresenter?.panelFrame
        let hit = app.testing_rootElement.hitTest(position: itemPos)
        let pointer = hit?.pointerTargetOnClick
        #expect(
            pointer != nil && String(describing: type(of: pointer!)).contains("Button"),
            "item hit=\(String(describing: hit.map { type(of: $0) })) pointer=\(String(describing: pointer.map { type(of: $0) })) frame=\(item.absoluteFrame)"
        )
        try await clickAt(itemPos, on: app)
        #expect(box.taps == 1, "menu item press must fire (taps=\(box.taps)) panel=\(String(describing: panel)) inPanel=\(panel?.contains(itemPos) ?? false)")
        #expect(app.window.popupPresenter?.isPresented == false)
    }

    /// Logorythia HistoryItemView shape: Menu lives inside a row Button and only
    /// appears while hovered. Opening/clicking the Menu must not fire the row,
    /// and the delete item must activate (regression target for nested Menu).
    @Test func menuInsideHoveredButtonRowActivatesItem() async throws {
        final class Box {
            var rowTaps = 0
            var deleteTaps = 0
        }
        let box = Box()
        struct Root: View {
            let box: Box
            @State var onHover = false
            var body: some View {
                Button {
                    box.rowTaps += 1
                } label: {
                    HStack {
                        Text("row-title")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if onHover {
                            Menu {
                                Button("confirm") { box.deleteTaps += 1 }
                            } label: {
                                Text("delete")
                            }
                        } else {
                            Text("time")
                        }
                    }
                    .onHover { onHover = $0 }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 12))

        let row = try #require(findButtonLabeled("row-title", in: app.testing_rootElement))
        let rowPos = center(of: row)
        try await app.testing_turn(input: .mouse(MouseEvent(position: rowPos, type: .move)))
        #expect(findButtonLabeled("delete", in: app.testing_rootElement) != nil, "hover must reveal Menu")

        let delete = try #require(findButtonLabeled("delete", in: app.testing_rootElement))
        let deletePos = center(of: delete)
        try await clickAt(deletePos, on: app)
        #expect(box.rowTaps == 0, "opening nested Menu must not fire outer row Button (rowTaps=\(box.rowTaps))")
        #expect(app.window.popupPresenter?.isPresented == true, "nested Menu must open")

        let confirm = try #require(findButtonLabeled("confirm", in: app.testing_rootElement))
        let confirmPos = center(of: confirm)
        try await clickAt(confirmPos, on: app)
        #expect(box.deleteTaps == 1, "confirm item must fire (deleteTaps=\(box.deleteTaps))")
        #expect(box.rowTaps == 0, "confirm must not fire outer row (rowTaps=\(box.rowTaps))")
    }
    
    @Test func lazyHistoryRowHoverMenuAppearsAndClears() async throws {
        struct Row: Identifiable {
            let id: Int
            let title: String
        }
        struct Root: View {
            @State var hovered: Set<Int> = []
            let rows = (0 ..< 8).map { Row(id: $0, title: "row-\($0)") }
            var body: some View {
                ScrollView {
                    LazyVStack {
                        ForEach(rows) { row in
                            Button {} label: {
                                HStack {
                                    Text(row.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    ZStack(alignment: .trailing) {
                                        Text("time-\(row.id)")
                                            .hidden(hovered.contains(row.id))
                                        Menu {
                                            Button("confirm-\(row.id)") {}
                                        } label: {
                                            Text("delete-\(row.id)")
                                        }
                                        .hidden(!hovered.contains(row.id))
                                    }
                                }
                            }
                            .onHover { isOn in
                                if isOn {
                                    hovered.insert(row.id)
                                } else {
                                    hovered.remove(row.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 12))

        let title = try #require(findButtonLabeled("row-2", in: app.testing_rootElement))
        let pos = center(of: title)
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .move)))
        let delete = try #require(findButtonLabeled("delete-2", in: app.testing_rootElement))
        #expect(delete.absoluteFrame.size.width > 0, "hover must reveal delete with real frame")

        // Leave the row — trailing control must no longer be the delete Menu.
        try await app.testing_turn(
            input: .mouse(MouseEvent(position: Position(column: 0, line: 11), type: .move))
        )
        let trailing = Position(
            column: title.absoluteFrame.position.column + title.absoluteFrame.size.width - 2,
            line: title.absoluteFrame.position.line
        )
        let afterLeave = app.testing_rootElement.pointerGestureTarget(at: trailing)
        let afterName = afterLeave.map { String(describing: type(of: $0)) } ?? "nil"
        let afterLabel = afterLeave.flatMap { textLabel(in: $0) }
        #expect(
            afterLabel != "delete-2",
            "leave must hide delete Menu (got \(afterName) label=\(String(describing: afterLabel)))"
        )
    }

    /// Outside dismiss must not leave the Menu trigger press-armed (would skip
    /// the next open). Anchor presses fall through to toggle.
    @Test func menuTriggerOpensAfterOutsideDismiss() async throws {
        struct Root: View {
            var body: some View {
                VStack {
                    Menu("menu") {
                        Button("item") {}
                    }
                    Text("outside")
                        .frame(width: 10, height: 2)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let menu = try #require(findButtonLabeled("menu", in: app.testing_rootElement))
        let menuPos = center(of: menu)
        try await clickAt(menuPos, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        // Far from menu/panel (panel may cover the "outside" label in a small grid).
        let outsidePos = Position(column: 0, line: 15)
        try await app.testing_turn(input: .mouse(MouseEvent(position: outsidePos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: outsidePos, type: .released(.left))))
        #expect(app.window.popupPresenter?.isPresented == false)

        // Immediate re-open must work (regression: armed gesture swallowed this).
        try await clickAt(menuPos, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)
    }

    @Test func underlyingOnHoverSuppressedWhileMenuOpen() async throws {
        final class Box {
            var events: [Bool] = []
        }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text("under-target")
                        .frame(maxWidth: .infinity, minHeight: 3)
                        .onHover { box.events.append($0) }
                    Menu("menu") {
                        Button("item") {}
                    }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let under = try #require(findText(in: app.testing_rootElement, equalTo: "under-target"))
        let underPos = under.absoluteFrame.position

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: underPos, type: .move))
        )
        #expect(box.events.last == true)

        let menu = try #require(findButtonLabeled("menu", in: app.testing_rootElement))
        let menuPos = menu.absoluteFrame.position
        let beforeOpen = box.events.count
        try await clickAt(menuPos, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        // Leaving the underlying row to click the Menu can send one onHover(false);
        // once presented, further moves must stay isolated (checked below).
        let duringOpen = Array(box.events.dropFirst(beforeOpen))
        #expect(duringOpen.filter { $0 == false }.count <= 1, "underlying onHover false while presenting: \(duringOpen)")

        let beforeMove = box.events.count
        try await app.testing_turn(
            input: .mouse(MouseEvent(position: underPos, type: .move))
        )
        let afterMove = Array(box.events.dropFirst(beforeMove))
        #expect(afterMove.isEmpty, "underlying onHover while menu open: \(afterMove)")
    }

    @Test func borderedTextFieldBorderClickFocusesField() async throws {
        struct Root: View {
            @State var text = ""
            @State var other = ""
            var body: some View {
                VStack {
                    // Buttons are not keyboard first-responders; use another
                    // field as the "focus was elsewhere" baseline.
                    TextField(text: $other, prompt: "other")
                    TextField(text: $text, prompt: "ph")
                        .border()
                        .padding(1)
                        .frame(width: 22)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 10))

        let fields = findAllTextFields(in: app.testing_rootElement)
        #expect(fields.count >= 2)
        let other = fields[0]
        let field = fields[1]
        app.window.setFirstResponder(other)
        #expect(app.window.firstResponder === other)

        let borderPos = field.absoluteFrame.position - Position(column: 1, line: 1)
        let hit = try #require(app.testing_rootElement.hitTest(position: borderPos))
        #expect(String(describing: type(of: hit)).contains("Border"))
        #expect(hit.focusTargetOnClick === field)

        try await app.testing_turn(input: .mouse(MouseEvent(position: borderPos, type: .pressed(.left))))
        #expect(app.window.firstResponder === field)
    }

    @Test func navigationPushForcesFullWindowPaint() async throws {
        struct Root: View {
            var body: some View {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ghost-marker-AAA")
                        Text("ghost-marker-BBB")
                        NavigationLink("go", value: 1)
                    }
                    .navigationDestination(for: Int.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("page-two")
                            Text("only-here")
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let go = try #require(findButtonLabeled("go", in: app.testing_rootElement))
        try await clickAt(go.absoluteFrame.position, on: app)

        #expect(findText(in: app.testing_rootElement, equalTo: "page-two") != nil)
        let paint = try #require(app.testing_lastPaintRect)
        let win = app.window.layer.frame.size
        #expect(paint.position == .zero)
        #expect(paint.size.width == win.width)
        #expect(paint.size.height == win.height)
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
private func findText(in control: Element?, equalTo value: String) -> Element? {
    guard let control else { return nil }
    if textLabel(in: control) == value { return control }
    for child in control.children {
        if let found = findText(in: child, equalTo: value) { return found }
    }
    return nil
}

@MainActor
private func findButtonLabeled(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"), textLabel(in: root) == label {
        return root
    }
    // Menu trigger may append indicator.
    if String(describing: type(of: root)).contains("Button"),
       let text = textLabel(in: root),
       text.hasPrefix(label) {
        return root
    }
    for child in root.children {
        if let found = findButtonLabeled(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func findTextField(in control: Element?) -> Element? {
    findAllTextFields(in: control).first
}

@MainActor
private func findAllTextFields(in control: Element?) -> [Element] {
    guard let control else { return [] }
    var result: [Element] = []
    if String(describing: type(of: control)).contains("TextField") {
        result.append(control)
    }
    for child in control.children {
        result.append(contentsOf: findAllTextFields(in: child))
    }
    return result
}

@MainActor
private func clickAt(_ pos: Position, on app: Application) async throws {
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
}

@MainActor
private func center(of control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
}
