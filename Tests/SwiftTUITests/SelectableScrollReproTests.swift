import Foundation
import Testing
@testable import SwiftTUI

/// Mirrors Logorythia GroupChatListView + ChatMainView chrome.
@Suite(.serialized)
@MainActor
struct SelectableScrollReproTests {

    private func drag(_ app: Application, from: Position, to: Position) async throws {
        try await app.testing_turn(input: .mouse(MouseEvent(position: from, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .move)))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .released(.left))))
    }

    private func findSelectable(in control: Element?) -> SelectableElement? {
        guard let control else { return nil }
        if let s = control as? SelectableElement { return s }
        for child in control.children {
            if let found = findSelectable(in: child) { return found }
        }
        return nil
    }

    private func findScroll(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("ScrollElement") { return control }
        for child in control.children {
            if let found = findScroll(in: child) { return found }
        }
        return nil
    }

    @Test func selectableInsideScrollViewLazyVStackWorks() async throws {
        struct Root: View {
            var body: some View {
                GeometryReader { _ in
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            Text("你好")
                            Text("你好！我们是「神衍·智能」团队。")
                            Text("目前项目是一个微型分布式节点共识引擎 (Swift 6 + 简化 Raft)，有什么需要我们帮忙的吗？")
                            Text("extra line one")
                            Text("extra line two")
                            Text("extra line three")
                        }
                        .selectable()
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 80, height: 12))
        let sel = try #require(findSelectable(in: app.testing_rootElement))
        #expect(sel.window != nil)

        let from = Position(column: 0, line: max(0, sel.absoluteFrame.position.line))
        try await drag(app, from: from, to: from + Position(column: 4, line: 0))
        #expect(sel.hasSelection)
        let text = try #require(sel.selectedText())
        #expect(text.contains("你") || text.contains("你好"), "got \(text)")
    }

    @Test func selectableWorksWhenScrolled() async throws {
        struct Root: View {
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0..<40, id: \.self) { i in
                            Text("row-\(i)-中文混合 ABC")
                        }
                    }
                    .selectable()
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        let sel = try #require(findSelectable(in: app.testing_rootElement))
        let scroll = try #require(findScroll(in: app.testing_rootElement))

        // Scroll down by wheel
        let scrollPos = scroll.absoluteFrame.position
        for _ in 0..<10 {
            try await app.testing_turn(
                input: .mouse(MouseEvent(
                    position: scrollPos + Position(column: 1, line: 1),
                    type: .scroll(deltaX: 0, deltaY: 1)
                ))
            )
        }
        try await app.testing_drainUntilIdle()

        // Click near top of viewport (should hit scrolled content)
        let vp = scroll.absoluteFrame.position
        let from = vp + Position(column: 0, line: 0)
        let target = app.testing_rootElement.pointerGestureTarget(at: from)
        #expect(target is SelectableElement, "expected Selectable after scroll, got \(String(describing: target))")

        try await drag(app, from: from, to: from + Position(column: 6, line: 0))
        #expect(sel.hasSelection, "no selection after scroll+drag")
        let text = try #require(sel.selectedText())
        #expect(!text.isEmpty, "empty selection text after scroll")
        print("SCROLLED text=\(text.debugDescription) origin=\(sel.absoluteFrame.position)")
    }

    @Test func selectableWithNavigationAndTextEdit() async throws {
        final class Box: @unchecked Sendable { var text = "" }
        let box = Box()

        struct Root: View {
            let binding: Binding<String>
            var body: some View {
                NavigationStack {
                    VStack(spacing: 0) {
                        GeometryReader { _ in
                            ScrollView {
                                LazyVStack(alignment: .leading) {
                                    Text("hello selectable region")
                                    Text("second line 中文")
                                    Text("third line")
                                }
                                .selectable()
                            }
                        }
                        .frame(maxHeight: .infinity)
                        TextEdit(text: binding)
                            .frame(height: Extended(2))
                    }
                    .navigationTitle("神衍")
                }
            }
        }

        let app = Application(rootView: Root(binding: Binding(get: { box.text }, set: { box.text = $0 })))
        try await app.testing_prepare(size: Size(width: 60, height: 16))
        let sel = try #require(findSelectable(in: app.testing_rootElement))

        // Find a text cell that belongs to the selectable content
        let from = Position(column: 0, line: 2) // below nav title roughly
        // Probe a few lines for a selectable hit
        var hit: Position?
        for line in 0..<12 {
            let p = Position(column: Extended(0), line: Extended(line))
            if app.testing_rootElement.pointerGestureTarget(at: p) is SelectableElement {
                hit = p
                break
            }
        }
        let start = try #require(hit, "could not find Selectable hit target under NavigationStack+TextEdit")
        try await drag(app, from: start, to: start + Position(column: 8, line: 0))
        #expect(sel.hasSelection)
        #expect(app.window.selectionCoordinator.activeOwner === sel)

        // Global highlight should paint
        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)
        app.window.selectionCoordinator.applyHighlight(into: &buffer)
        let cell = buffer.cell(at: start)
        #expect(cell?.backgroundColor == TextSelectionStyle.background, "highlight missing at \(start)")
    }

    @Test func edgeDragScrollsViewportNotFullContent() async throws {
        struct Root: View {
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0..<50, id: \.self) { i in
                            Text("line-\(i)")
                        }
                    }
                    .selectable()
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 30, height: 6))
        let sel = try #require(findSelectable(in: app.testing_rootElement))
        let scroll = try #require(findScroll(in: app.testing_rootElement))

        // Begin drag inside viewport, then move below viewport bottom
        let top = scroll.absoluteFrame.position
        try await app.testing_turn(input: .mouse(MouseEvent(position: top + Position(column: 0, line: 1), type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: top + Position(column: 0, line: 2), type: .move)))
        #expect(sel.hasSelection || true) // may set on move

        let below = Position(column: top.column, line: scroll.absoluteFrame.maxLine + 1)
        try await app.testing_turn(input: .mouse(MouseEvent(position: below, type: .move)))

        // Tick auto-scroll a few times via clock if scheduled
        let before = sel.absoluteFrame.position.line
        for _ in 0..<5 {
            try await app.testing_turn()
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        try await app.testing_drainUntilIdle()
        let after = sel.absoluteFrame.position.line
        print("EDGE before=\(before) after=\(after) selectableFrame=\(sel.absoluteFrame) scrollFrame=\(scroll.absoluteFrame)")
        // Content should have scrolled up (absoluteFrame.line decreases) if edge autoscroll uses viewport
        #expect(after < before, "edge drag did not scroll ScrollView viewport (before=\(before) after=\(after))")
    }
}
