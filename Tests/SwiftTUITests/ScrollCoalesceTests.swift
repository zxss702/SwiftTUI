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

    /// 嵌套滚动：内层 ScrollView 内容放得下（maxOffset=0）时必须把滚轮事件
    /// 让给外层，否则外层永远收不到 —— 设置 sheet 滚不动的回归。
    private struct NestedRoot: View {
        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    Text("top")
                    ScrollView {
                        Text("inner fits")
                    }
                    .frame(width: 20, height: 1)
                    ForEach(0..<30, id: \.self) { i in
                        Text("bottom \(i)")
                    }
                }
            }
        }
    }

    private func firstScrollElement(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("ScrollElement") { return control }
        for child in control.children {
            if let found = firstScrollElement(in: child) { return found }
        }
        return nil
    }

    @Test func scrollOverUnscrollableInnerReachesOuter() async throws {
        let app = Application(rootView: NestedRoot())
        try await app.testing_prepare(size: Size(width: 30, height: 8))

        let outer = try #require(firstScrollElement(in: app.testing_rootElement))
        let inner = try #require(findScrollableInner(in: app.testing_rootElement))
        let content = try #require(outer.children.first)
        let innerPos = inner.absoluteFrame.position

        // 滚轮落在内层区域 —— 内层 maxOffset=0 应放行给外层
        let baseline = content.absoluteFrame.position.line
        app.handleTerminalEvent(.mouse(MouseEvent(position: innerPos, type: .scroll(deltaX: 0, deltaY: 3))))
        _ = try await app.settleHost()
        #expect(content.absoluteFrame.position.line < baseline,
                "滚轮被内层吞掉，外层没动 (baseline=\(baseline) after=\(content.absoluteFrame.position.line))")
    }

    private func findScrollableInner(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("ScrollElement") {
            var ancestor = control.parent
            while let node = ancestor {
                if String(describing: type(of: node)).contains("ScrollElement") {
                    return control
                }
                ancestor = node.parent
            }
        }
        for child in control.children {
            if let found = findScrollableInner(in: child) { return found }
        }
        return nil
    }
}
