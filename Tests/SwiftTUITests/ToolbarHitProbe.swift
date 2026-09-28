import Foundation
import Observation
import Testing
@testable import SwiftTUI

@Observable
@MainActor
private final class ToolbarProbeObs {
    var record: String? = nil
}

/// 动态 ToolbarContent：内容读取 @Observable，变化后必须重新收集并可命中。
private struct ProbeToolbar: ToolbarContent {
    @Bindable var obs: ToolbarProbeObs

    var body: some ToolbarContent {
        if obs.record != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("黑板") {}
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("任务") {}
            }
        }
    }
}

@Suite(.serialized)
@MainActor
struct ToolbarHitProbe {
    /// Regression: a `ToolbarContent` whose `body` gates on an `@Observable`
    /// must re-collect when the observed value changes — the bar must rebuild
    /// with the new trailing items and those items must be hit-testable.
    @Test func dynamicToolbarContentStructReCollects() async throws {
        let size = Size(width: 50, height: 14)
        let obs = ToolbarProbeObs()

        struct Root: View {
            let obs: ToolbarProbeObs
            var body: some View {
                NavigationStack {
                    Content(obs: obs)
                        .navigationTitle("Title")
                        .toolbar {
                            ProbeToolbar(obs: obs)
                        }
                }
            }
        }
        struct Content: View {
            let obs: ToolbarProbeObs
            var body: some View {
                Text("content \(obs.record ?? "nil")")
            }
        }

        let app = Application(rootView: Root(obs: obs))
        try await app.testing_prepareVT(size: size)

        func buttonElements(atRow row: Int) -> [Element] {
            var found: [Element] = []
            func walk(_ el: Element) {
                if String(describing: type(of: el)).contains("ButtonElement"),
                   el.absoluteFrame.position.line.intValue == row
                {
                    found.append(el)
                }
                for c in el.children { walk(c) }
            }
            walk(app.testing_rootElement)
            return found
        }

        #expect(buttonElements(atRow: 0).isEmpty)

        obs.record = "r1"
        try await app.testing_drainUntilIdle()

        let buttons = buttonElements(atRow: 0)
        #expect(buttons.count == 2)

        // Each button must resolve as the pointer-gesture target at its frame.
        for b in buttons {
            let f = b.absoluteFrame
            let mid = Position(column: f.position.column + f.size.width / 2, line: f.position.line)
            let target = app.testing_rootElement.pointerGestureTarget(at: mid)
            #expect(target === b)
        }
    }
}
