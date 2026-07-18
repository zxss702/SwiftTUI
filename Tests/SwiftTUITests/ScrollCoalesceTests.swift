import Foundation
import Testing
@testable import SwiftTUI

/// Wheel deltas are coalesced and applied once per frame in `update()`.
/// Two opposite deltas in the same frame must cancel (no scroll); several
/// same-direction deltas must apply their sum. This guards the fix where a
/// direction reversal used to lag behind queued forward events.
@Suite(.serialized)
@MainActor
struct ScrollCoalesceTests {

    private struct Root: View {
        var body: some View {
            GeometryReader { _ in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0..<40, id: \.self) { i in
                            Text("row \(i)")
                        }
                    }
                    .selectable()
                }
            }
        }
    }

    private func findSelectable(in control: Element?) -> SelectableElement? {
        guard let control else { return nil }
        if let s = control as? SelectableElement { return s }
        for child in control.children {
            if let found = findSelectable(in: child) { return found }
        }
        return nil
    }

    @Test func reverseScrollInSameFrameCancels() async throws {
        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 8))

        let sel = try #require(findSelectable(in: app.testing_rootElement))
        let baseline = sel.absoluteFrame.position.line
        let pos = Position(column: 1, line: 1)

        // Net forward scroll (sum applied once) moves content up.
        app.handleTerminalEvent(.mouse(MouseEvent(position: pos, type: .scroll(deltaX: 0, deltaY: 3))))
        app.handleTerminalEvent(.mouse(MouseEvent(position: pos, type: .scroll(deltaX: 0, deltaY: 3))))
        _ = try await app.settleHost()
        let afterForward = sel.absoluteFrame.position.line
        #expect(afterForward < baseline, "net forward scroll did not move content (baseline=\(baseline) after=\(afterForward))")

        // Opposite deltas in the same frame cancel to a no-op.
        let anchor = afterForward
        app.handleTerminalEvent(.mouse(MouseEvent(position: pos, type: .scroll(deltaX: 0, deltaY: 4))))
        app.handleTerminalEvent(.mouse(MouseEvent(position: pos, type: .scroll(deltaX: 0, deltaY: -4))))
        _ = try await app.settleHost()
        #expect(sel.absoluteFrame.position.line == anchor, "opposite same-frame scrolls should cancel (anchor=\(anchor) after=\(sel.absoluteFrame.position.line))")
    }
}
