import Foundation
import Testing
@testable import SwiftTUI

/// Repro: pinned section footer + onHover inside ScrollView { LazyVGrid }.
/// Mirrors Logorythia `SYAgentDiffLineView` / `SYDiffView`.
@Suite(.serialized)
@MainActor
struct LazyVGridPinnedFooterHoverTests {

    final class HoverBox: @unchecked Sendable {
        var events: [Bool] = []
        var last: Bool?
    }

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

    private func findScroll(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("ScrollElement") { return control }
        for child in control.children {
            if let found = findScroll(in: child) { return found }
        }
        return nil
    }

    /// Empty `Section {}` footer — known-good baseline.
    @Test func emptySectionPinnedFooterOnHoverFires() async throws {
        let box = HoverBox()
        struct Root: View {
            let box: HoverBox
            @State var isHover = false
            var body: some View {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 8, maximum: .infinity)),
                            GridItem(.flexible(minimum: 8, maximum: .infinity)),
                        ],
                        alignment: .leading,
                        spacing: 1,
                        pinnedViews: .sectionFooters
                    ) {
                        Section {} footer: {
                            HStack {
                                Text("最新")
                                if isHover {
                                    Text("menu")
                                }
                            }
                            .onHover {
                                box.events.append($0)
                                box.last = $0
                                isHover = $0
                            }
                        }
                        ForEach(0..<12, id: \.self) { i in
                            Text("cell-\(i)")
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 10))

        let label = try #require(findTextElement("最新", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.events.contains(true), "events=\(box.events) frame=\(onHover.absoluteFrame)")
    }

    /// Cells live inside the same Section as the footer (SYDiffView shape).
    @Test func sectionWithCellsPinnedFooterOnHoverFires() async throws {
        let box = HoverBox()
        struct Root: View {
            let box: HoverBox
            var body: some View {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 1,
                        pinnedViews: .sectionFooters
                    ) {
                        Section {
                            ForEach(0..<12, id: \.self) { i in
                                Text("cell-\(i)")
                            }
                        } footer: {
                            Text("时间戳")
                                .onHover {
                                    box.events.append($0)
                                    box.last = $0
                                }
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 10))

        let label = try #require(findTextElement("时间戳", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.events.contains(true), "events=\(box.events) frame=\(onHover.absoluteFrame)")
    }

    /// Multiple non-empty sections — Logorythia history list shape.
    @Test func multipleSectionFootersOnHoverFires() async throws {
        let boxes = (0..<3).map { _ in HoverBox() }
        struct Root: View {
            let boxes: [HoverBox]
            var body: some View {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ],
                        alignment: .leading,
                        spacing: 1,
                        pinnedViews: .sectionFooters
                    ) {
                        Section {} footer: {
                            Text("最新")
                        }
                        ForEach(0..<3, id: \.self) { section in
                            Section {
                                ForEach(0..<8, id: \.self) { i in
                                    Text("s\(section)-c\(i)")
                                }
                            } footer: {
                                Text("foot-\(section)")
                                    .onHover {
                                        boxes[section].events.append($0)
                                        boxes[section].last = $0
                                    }
                            }
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root(boxes: boxes))
        try await app.testing_prepare(size: Size(width: 60, height: 16))

        // Hover each section footer that is currently mounted.
        for section in 0..<3 {
            let label = findTextElement("foot-\(section)", in: app.testing_rootElement)
            guard let label else { continue }
            let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
            boxes[section].events.removeAll()
            let pos = center(of: onHover)
            try await app.testing_turn(
                input: .mouse(MouseEvent(position: pos, type: .move))
            )
            try await app.testing_drainUntilIdle()
            #expect(
                boxes[section].events.contains(true),
                "section \(section) onHover failed; events=\(boxes[section].events) frame=\(onHover.absoluteFrame) hit=\(String(describing: app.testing_rootElement.hitTest(position: pos).map { type(of: $0) }))"
            )
        }

        #expect(
            boxes.contains(where: { $0.events.contains(true) }),
            "at least one mounted footer must accept hover"
        )
    }


    /// Real app shape: `if isHover { … }` truly inserts/removes from the tree
    /// (not `.hidden`). Hover(true) must survive the footer remount.
    @Test func sectionFooterHoverSurvivesConditionalMenu() async throws {
        let box = HoverBox()
        struct Root: View {
            let box: HoverBox
            @State var isHover = false
            var body: some View {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ],
                        alignment: .leading,
                        spacing: 1,
                        pinnedViews: .sectionFooters
                    ) {
                        Section {
                            ForEach(0..<8, id: \.self) { i in
                                Text("file-\(i)")
                            }
                        } footer: {
                            HStack {
                                GeometryReader { size in
                                    Text(String(repeating: "─", count: size.widthInt))
                                }
                                .frame(maxWidth: .infinity)

                                Text("时间戳")

                                GeometryReader { size in
                                    Text(String(repeating: "─", count: size.widthInt))
                                }
                                .frame(maxWidth: .infinity)

                                if isHover {
                                    Text("切换至此")
                                }
                            }
                            .onHover {
                                box.events.append($0)
                                box.last = $0
                                isHover = $0
                            }
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 60, height: 12))

        let label = try #require(findTextElement("时间戳", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.events.contains(true), "initial hover true; events=\(box.events)")
        #expect(box.last == true, "must stay hovered after if-insert remount; events=\(box.events) last=\(String(describing: box.last))")
        // Menu/button must actually appear in the tree (not merely hidden).
        #expect(findTextElement("切换至此", in: app.testing_rootElement) != nil)

        let label2 = try #require(findTextElement("时间戳", in: app.testing_rootElement))
        let onHover2 = try #require(findAncestor(of: label2, named: "OnHoverElement"))
        let pos2 = center(of: onHover2)
        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos2, type: .move))
        )
        try await app.testing_drainUntilIdle()
        #expect(box.last == true, "after second move; events=\(box.events)")
    }

    /// After scroll, empty-band footer naturalY=0 should leave the viewport.
    @Test func emptySectionFooterDoesNotStickAfterScroll() async throws {
        let box = HoverBox()
        struct Root: View {
            let box: HoverBox
            var body: some View {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 0,
                        pinnedViews: .sectionFooters
                    ) {
                        Section {} footer: {
                            Text("最新").onHover {
                                box.events.append($0)
                                box.last = $0
                            }
                        }
                        ForEach(0..<40, id: \.self) { i in
                            Text("cell-\(i)")
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 8))

        let scroll = try #require(findScroll(in: app.testing_rootElement))
        let scrollPos = scroll.absoluteFrame.position
        for _ in 0..<6 {
            try await app.testing_turn(
                input: .mouse(MouseEvent(
                    position: scrollPos + Position(column: 1, line: 1),
                    type: .scroll(deltaX: 0, deltaY: 1)
                ))
            )
        }
        try await app.testing_drainUntilIdle()

        let label = findTextElement("最新", in: app.testing_rootElement)
        if let label {
            let onHover = findAncestor(of: label, named: "OnHoverElement")
            let frame = onHover?.absoluteFrame ?? .zero
            let vp = scroll.absoluteFrame
            #expect(
                !vp.contains(frame.position),
                "empty Section {} footer must not remain pinned in viewport after scroll; frame=\(frame) vp=\(vp)"
            )
        }
    }
}
