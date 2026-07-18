import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct GeometryReaderScrollTests {

    @Test func geometryReaderOutsideScrollViewGetsViewportWidth() async throws {
        final class Box: @unchecked Sendable { var width = -1 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                GeometryReader { size in
                    let _ = { box.width = size.widthInt }()
                    ScrollView {
                        Text("w=\(size.widthInt)")
                    }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 80, height: 24))
        #expect(box.width == 80, "got \(box.width)")
    }

    @Test func geometryReaderInsideScrollViewLazyVStackGetsStackWidth() async throws {
        final class Box: @unchecked Sendable {
            var widths: [Int] = []
            var lastWidth = -1
        }
        let box = Box()
        struct Row: View {
            let box: Box
            let id: Int
            var body: some View {
                GeometryReader { size in
                    let _ = {
                        box.widths.append(size.widthInt)
                        box.lastWidth = size.widthInt
                    }()
                    Text("row \(id) w=\(size.widthInt)")
                }
            }
        }
        struct Root: View {
            let box: Box
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0..<3, id: \.self) { i in
                            Row(box: box, id: i)
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 80, height: 24))
        try await app.testing_drainUntilIdle()
        #expect(box.lastWidth == 80, "stable width should be viewport, got \(box.lastWidth)")
        // First `size(proposed:)` must publish the stack width before content
        // that reads `widthInt` is measured — placeholder `1` must not win.
        #expect(
            box.widths.contains(80),
            "never published viewport width: \(box.widths)"
        )
        let lastThree = Array(box.widths.suffix(3))
        #expect(
            lastThree.allSatisfy { $0 == 80 },
            "layout must settle on width 80, got \(box.widths)"
        )
    }

    @Test func geometryReaderInsideScrollViewWithNavChrome() async throws {
        final class Box: @unchecked Sendable { var width = -1 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                GeometryReader { _ in
                    NavigationStack {
                        VStack(spacing: 0) {
                            GeometryReader { size in
                                let _ = { box.width = size.widthInt }()
                                ScrollView {
                                    LazyVStack {
                                        Text("hello \(size.widthInt)")
                                    }
                                }
                            }
                            .frame(maxHeight: .infinity)
                            Text("footer")
                        }
                        .navigationTitle("t")
                    }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 88, height: 29))
        try await app.testing_drainUntilIdle()
        #expect(box.width == 88, "got \(box.width)")
    }

    /// size 不变不重建：稳定后多次 layout / 滚动不应继续增加 build 次数。
    @Test func geometryReaderDoesNotRebuildWhenSizeUnchanged() async throws {
        final class Box: @unchecked Sendable {
            var builds = 0
            var widths: [Int] = []
        }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                HStack {
                    GeometryReader { size in
                        let _ = {
                            box.builds += 1
                            box.widths.append(size.widthInt)
                        }()
                        Text("w=\(size.widthInt)")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("side")
                }
            }
        }

        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 60, height: 10))
        try await app.testing_drainUntilIdle()
        let buildsAfterSettle = box.builds
        #expect(buildsAfterSettle >= 1)
        #expect(!box.widths.contains(0), "0-width probes must not publish: \(box.widths)")

        app.requestLayout()
        try await app.testing_drainUntilIdle()
        app.requestLayout()
        try await app.testing_drainUntilIdle()

        #expect(
            box.builds == buildsAfterSettle,
            "same size must not rebuild (was \(buildsAfterSettle), now \(box.builds))"
        )
    }
}
