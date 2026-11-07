import Foundation
import Testing
@testable import SwiftTUI

/// Placement rules: an anchor hugging an edge pops inward from that edge
/// (top → below, bottom → above, left → trailing, right → leading); anchors
/// away from edges pop toward whichever axis side has more room.
@Suite(.serialized)
@MainActor
struct PopoverPlacementTests {
    private struct Anchor<Content: View>: View {
        let alignment: Alignment
        @ViewBuilder var content: () -> Content
        var body: some View {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }

    private struct Host: View {
        let alignment: Alignment
        @State var show = false
        var body: some View {
            Anchor(alignment: alignment) {
                Button("pop") { show.toggle() }
                    .popover(isPresented: $show) {
                        Text("popover-body")
                            .frame(width: 20, height: 6)
                    }
            }
        }
    }

    private func panelRect(in root: Element) -> Rect? {
        func textLabel(_ el: Element) -> String? {
            if let t = Mirror(reflecting: el).children.first(where: { $0.label == "text" })?.value as? String {
                return t
            }
            for c in el.children {
                if let t = textLabel(c) { return t }
            }
            return nil
        }
        var deepest: Element? = nil
        func find(_ el: Element) {
            if textLabel(el) == "popover-body" { deepest = el }
            for c in el.children { find(c) }
        }
        find(root)
        return deepest?.absoluteFrame
    }

    private func anchorRect(in root: Element) -> Rect? {
        func find(_ el: Element) -> Element? {
            if String(describing: type(of: el)).contains("Button") {
                return el
            }
            for c in el.children {
                if let f = find(c) { return f }
            }
            return nil
        }
        return find(root)?.absoluteFrame
    }

    private func open(alignment: Alignment) async throws -> (Application, Rect, Rect) {
        let app = Application(rootView: Host(alignment: alignment))
        try await app.testing_prepare(size: Size(width: 60, height: 20))
        let anchor = try #require(anchorRect(in: app.testing_rootElement))
        let pressPos = Position(column: anchor.position.column + 1, line: anchor.position.line)
        try await app.testing_turn(input: .mouse(MouseEvent(position: pressPos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pressPos, type: .released(.left))))
        let panel = try #require(panelRect(in: app.testing_rootElement))
        return (app, anchor, panel)
    }

    @Test func topEdgeAnchorPopsBelow() async throws {
        let (_, anchor, panel) = try await open(alignment: .topLeading)
        #expect(panel.position.line >= anchor.position.line + anchor.size.height)
    }

    @Test func bottomEdgeAnchorPopsAbove() async throws {
        let (_, anchor, panel) = try await open(alignment: .bottomLeading)
        #expect(panel.position.line + panel.size.height <= anchor.position.line)
    }

    @Test func rightEdgeAnchorPopsLeading() async throws {
        let (_, anchor, panel) = try await open(alignment: .trailing)
        #expect(panel.position.column + panel.size.width <= anchor.position.column)
    }

    @Test func leftEdgeAnchorPopsTrailing() async throws {
        let (_, anchor, panel) = try await open(alignment: .leading)
        #expect(panel.position.column >= anchor.position.column + anchor.size.width)
    }
}
