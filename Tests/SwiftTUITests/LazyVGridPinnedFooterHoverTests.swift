import Foundation
import Testing
@testable import SwiftTUI

/// Repro: pinned section footer + onHover inside ScrollView { LazyVGrid }.
/// Mirrors Logorythia `SYAgentDiffLineView`: `Section {} footer: { … .onHover }`
/// with cells as siblings (not inside the section).
@Suite(.serialized)
@MainActor
struct LazyVGridPinnedFooterHoverTests {

    final class HoverBox: @unchecked Sendable {
        var events: [Bool] = []
        var last: Bool?
    }

    private func findLabeled(_ label: String, in root: Element?) -> Element? {
        guard let root else { return nil }
        if textLabel(in: root) == label { return root }
        for child in root.children {
            if let found = findLabeled(label, in: child) { return found }
        }
        return nil
    }

    private func textLabel(in control: Element) -> String? {
        if let text = Mirror(reflecting: control).children
            .first(where: { $0.label == "text" })?.value as? String {
            return text
        }
        for child in control.children {
            if let text = textLabel(in: child) { return text }
        }
        return nil
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

    /// App-shaped: empty `Section {}` footer + sibling ForEach cells.
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

        let label = try #require(findLabeled("最新", in: app.testing_rootElement))
        var walk: Element? = label
        var chain: [String] = []
        while let node = walk {
            let t = String(describing: type(of: node))
            chain.append("\(t) frame=\(node.absoluteFrame) parentNil=\(node.parent == nil)")
            walk = node.parent
        }
        print("PARENT_CHAIN:\n" + chain.joined(separator: "\n"))
        let onHover = findAncestor(of: label, named: "OnHover")
        let chrome = findAncestor(of: label, named: "SectionChromeElement")
        print("onHover=\(String(describing: onHover.map { type(of: $0) })) chrome=\(String(describing: chrome.map { type(of: $0) }))")
        // Fall back: hover via SectionChrome if OnHover missing
        let hoverTarget = onHover ?? chrome ?? label
        let scroll = try #require(findScroll(in: app.testing_rootElement))

        let footerFrame = hoverTarget.absoluteFrame
        let scrollFrame = scroll.absoluteFrame
        print("footerFrame=\(footerFrame) scrollFrame=\(scrollFrame)")
        #expect(
            footerFrame.size.height > 0 && footerFrame.size.width > 0,
            "footer frame must be non-empty: \(footerFrame)"
        )

        let pos = center(of: hoverTarget)
        let hit = app.testing_rootElement.hitTest(position: pos)
        print("pos=\(pos) hit=\(String(describing: hit.map { type(of: $0) }))")

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()
        print("events=\(box.events) last=\(String(describing: box.last))")

        #expect(
            box.events.contains(true),
            "onHover(true) must fire; events=\(box.events) chain=\(chain) hit=\(String(describing: hit.map { type(of: $0) })) pos=\(pos) footer=\(footerFrame)"
        )
    }

    /// Correct SwiftUI shape: cells live inside the same Section as the footer.
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
                            Text("最新")
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

        let label = try #require(findLabeled("最新", in: app.testing_rootElement))
        let onHover = try #require(findAncestor(of: label, named: "OnHoverElement"))
        let pos = center(of: onHover)

        try await app.testing_turn(
            input: .mouse(MouseEvent(position: pos, type: .move))
        )
        try await app.testing_drainUntilIdle()

        #expect(box.events.contains(true), "events=\(box.events) frame=\(onHover.absoluteFrame)")
    }

    /// After scroll, empty-band footer naturalY=0 should leave the viewport
    /// (pin clamps to natural=0), while a real section footer should stay hittable
    /// near the viewport bottom if layout re-runs.
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

        let label = findLabeled("最新", in: app.testing_rootElement)
        // Empty-section footer band is only ~1 row tall; after scroll it should
        // unload or sit above the viewport — not stick as a true pinned footer.
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
