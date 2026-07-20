import Foundation
import Testing
@testable import SwiftTUI

/// Repro: `if isHover { … } else { … }` rows inside `ScrollView { LazyVStack }`.
/// Mirrors Logorythia `HistoryItemView` (history list) and `ModelInfoRowView`
/// (settings model list). The branch swap mounts fresh 0×0 elements; LazyVStack
/// used to skip the row's `layout` because the measured row size was unchanged,
/// leaving the new elements invisible (blank on hover, no restore on leave).
@Suite(.serialized)
@MainActor
struct LazyVStackHoverConditionalTests {

    private func findTextElement(_ label: String, in root: Element?) -> Element? {
        guard let root else { return nil }
        if textOf(root) == label { return root }
        for child in root.children {
            if let found = findTextElement(label, in: child) { return found }
        }
        return nil
    }

    private func textOf(_ control: Element) -> String? {
        Mirror(reflecting: control).children
            .first(where: { $0.label == "text" })?
            .value as? String
    }

    private func center(of control: Element) -> Position {
        let frame = control.absoluteFrame
        return Position(
            column: frame.position.column + max(Extended(0), frame.size.width / 2),
            line: frame.position.line + max(Extended(0), frame.size.height / 2)
        )
    }

    private func findAncestor(
        of element: Element,
        named substring: String
    ) -> Element? {
        var current: Element? = element
        while let node = current {
            if String(describing: type(of: node)).contains(substring) {
                return node
            }
            current = node.parent
        }
        return nil
    }

    private func hasVisibleFrame(_ control: Element) -> Bool {
        let size = control.absoluteFrame.size
        return size.width > Extended(0) && size.height > Extended(0)
    }

    /// History list shape: trailing slot swaps time ↔ delete on hover.
    /// Enter must show a laid-out "删除"; leave must restore a laid-out time.
    @Test func lazyVStackRowSwapsTrailingSlotOnHoverAndRestoresOnLeave() async throws {
        struct Row: View {
            let index: Int
            @State var isHover = false
            var body: some View {
                HStack {
                    Text("对话-\(index)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .trailing) {
                        if isHover {
                            Text("删除")
                        } else {
                            Text("time-\(index)")
                        }
                    }
                }
                .onHover { isHover = $0 }
            }
        }
        struct Root: View {
            var body: some View {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { i in
                            Row(index: i)
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 20))

        let label = try #require(findTextElement("对话-1", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        let deleteText = try #require(
            findTextElement("删除", in: app.testing_rootElement),
            "hover must mount the 删除 branch"
        )
        #expect(
            hasVisibleFrame(deleteText),
            "删除 must be laid out (non-zero frame), got \(deleteText.absoluteFrame)"
        )
        #expect(findTextElement("time-1", in: app.testing_rootElement) == nil)

        // Leave: move well below the rows (still inside the window).
        try await app.testing_turn(
            input: .mouse(MouseEvent(position: Position(column: 1, line: 18), type: .move))
        )
        try await app.testing_drainUntilIdle()

        let timeText = try #require(
            findTextElement("time-1", in: app.testing_rootElement),
            "leave must restore the time branch"
        )
        #expect(
            hasVisibleFrame(timeText),
            "restored time text must be laid out (non-zero frame), got \(timeText.absoluteFrame)"
        )
        #expect(findTextElement("删除", in: app.testing_rootElement) == nil)
    }

    /// Settings model list shape: `if isHover { Text("⋯") }` appended at the
    /// row's trailing edge (no else branch).
    @Test func lazyVStackRowShowsTrailingDotsOnHover() async throws {
        struct Row: View {
            let index: Int
            @State var isHover = false
            var body: some View {
                HStack(spacing: 0) {
                    Text("model-\(index)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isHover {
                        Text("⋯")
                    }
                }
                .onHover { isHover = $0 }
            }
        }
        struct Root: View {
            var body: some View {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { i in
                            Row(index: i)
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let label = try #require(findTextElement("model-0", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        let dots = try #require(
            findTextElement("⋯", in: app.testing_rootElement),
            "hover must mount the ⋯ trigger"
        )
        #expect(
            hasVisibleFrame(dots),
            "⋯ must be laid out (non-zero frame), got \(dots.absoluteFrame)"
        )

        // Leave restores the plain row (⋯ removed).
        try await app.testing_turn(
            input: .mouse(MouseEvent(position: Position(column: 1, line: 14), type: .move))
        )
        try await app.testing_drainUntilIdle()
        #expect(findTextElement("⋯", in: app.testing_rootElement) == nil)
    }
}
