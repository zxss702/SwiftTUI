import Foundation
import Testing
@testable import SwiftTUI

/// Reproduces: closing a bordered popup/sheet presented over full-width CJK
/// text leaves torn glyphs / stale border characters behind (the dirty-rect
/// repaint after dismissal does not restore the straddled wide chars).
///
/// Runs the REAL VT double-buffer + damage pipeline (`testing_prepareVT`) so
/// the persistent back buffer and partial redraws behave like production —
/// a fresh full-tree render (as plain `testing_prepare` does) would hide the
/// bug because it never keeps stale cells.
@Suite(.serialized)
@MainActor
struct PopupCloseRestoreTests {

    /// After open→close, every screen cell must equal a clean full re-render of
    /// the (now popup-free) tree. Any mismatch is stale residue.
    private func expectScreenMatchesCleanRender(
        _ app: Application,
        size: Size,
        _ context: @autoclosure () -> String
    ) throws {
        var clean = ScreenBuffer(rect: Rect(position: .zero, size: size))
        app.window.layer.draw(into: &clean)

        var mismatches: [String] = []
        for line in 0 ..< size.height.intValue {
            for column in 0 ..< size.width.intValue {
                let pos = Position(column: Extended(column), line: Extended(line))
                let expected = clean.character(at: pos)
                let actual = app.testing_vtCharacter(at: pos)
                if expected != actual {
                    mismatches.append("(\(column),\(line)) want \(String(reflecting: expected)) got \(String(reflecting: actual))")
                }
            }
        }
        #expect(
            mismatches.isEmpty,
            "\(context()): \(mismatches.count) stale cells: \(mismatches.prefix(12).joined(separator: ", "))"
        )
    }

    @Test func sheetCloseRestoresCJKUnderlay() async throws {
        let size = Size(width: 40, height: 14)
        struct Root: View {
            @State var show = false
            var body: some View {
                VStack(spacing: 0) {
                    Button("open") { show = true }
                    ForEach(0..<12, id: \.self) { i in
                        Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 19))
                    }
                }
                .sheet(isPresented: $show) {
                    Button("close") { show = false }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)

        try await click(try #require(findButtonLabeled("open", in: app.testing_rootElement)), on: app)
        #expect(app.window.popupPresenter?.isPresented == true, "sheet should be open")

        try await click(try #require(findButtonLabeled("close", in: app.testing_rootElement)), on: app)
        #expect(app.window.popupPresenter?.isPresented == false, "sheet should be closed")

        try expectScreenMatchesCleanRender(app, size: size, "after sheet close")
    }

    @Test func popoverCloseRestoresCJKUnderlay() async throws {
        let size = Size(width: 44, height: 14)
        struct Root: View {
            @State var show = false
            var body: some View {
                VStack(spacing: 0) {
                    Button("open") { show = true }
                    ForEach(0..<12, id: \.self) { i in
                        Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 21))
                    }
                }
                .popover(isPresented: $show) {
                    Text("弹出内容")
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)

        try await click(try #require(findButtonLabeled("open", in: app.testing_rootElement)), on: app)
        #expect(app.window.popupPresenter?.isPresented == true, "popover should be open")

        // Escape dismisses the top presentation (routed to the floating host).
        try await app.testing_turn(input: .key(KeyEvent(
            character: "\u{1b}", keycode: VTKeyCode.escape, modifiers: [], type: .press
        )))
        try await app.testing_drainUntilIdle()
        #expect(app.window.popupPresenter?.isPresented == false, "popover should be closed")

        try expectScreenMatchesCleanRender(app, size: size, "after popover close")
    }

    /// Closest match to the real bug (AgentGroupChatUserView): a fixed-size
    /// popover panel centered over a `ScrollView { LazyVStack { CJK rows } }`.
    /// The panel is narrower than the window, so only a sub-rectangle is
    /// dismissed — the border-straddled underlay cells around the panel edges
    /// must be restored, not left torn.
    @Test func fixedSizePopoverOverScrollingCJKRestoresOnClose() async throws {
        let size = Size(width: 50, height: 16)
        struct Root: View {
            @State var show = false
            var body: some View {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Button("open") { show = true }
                        ForEach(0..<30, id: \.self) { i in
                            Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 24))
                        }
                    }
                }
                .popover(isPresented: $show) {
                    ScrollView {
                        Text(String(repeating: "面板内容行\n", count: 20))
                            .padding(.all, 1)
                    }
                    .frame(width: 30, height: 10)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)

        try await click(try #require(findButtonLabeled("open", in: app.testing_rootElement)), on: app)
        #expect(app.window.popupPresenter?.isPresented == true, "popover should be open")

        try await app.testing_turn(input: .key(KeyEvent(
            character: "\u{1b}", keycode: VTKeyCode.escape, modifiers: [], type: .press
        )))
        try await app.testing_drainUntilIdle()
        #expect(app.window.popupPresenter?.isPresented == false, "popover should be closed")

        try expectScreenMatchesCleanRender(app, size: size, "after fixed-size popover close")
    }
}

// MARK: - Helpers (file-local; other suites keep their own private copies)

@MainActor
private func pcrTextLabel(in control: Element) -> String? {
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
        return text
    }
    for child in control.children {
        if let text = pcrTextLabel(in: child) { return text }
    }
    return nil
}

@MainActor
private func findButtonLabeled(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"), pcrTextLabel(in: root) == label {
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
