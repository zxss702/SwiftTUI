import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct WidthReaderTests {

    @Test func widthReaderOutsideScrollViewGetsViewportWidth() async throws {
        final class Box: @unchecked Sendable { var width = -1 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                WidthReader { width in
                    let _ = { box.width = width }()
                    ScrollView {
                        Text("w=\(width)")
                    }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 80, height: 24))
        try await app.testing_drainUntilIdle()
        #expect(box.width == 80, "got \(box.width)")
    }

    @Test func widthReaderInsideScrollViewLazyVStackSettlesOnStackWidth() async throws {
        final class Box: @unchecked Sendable {
            var widths: [Int] = []
            var lastWidth = -1
        }
        let box = Box()
        struct Row: View {
            let box: Box
            let id: Int
            var body: some View {
                WidthReader { width in
                    let _ = {
                        box.widths.append(width)
                        box.lastWidth = width
                    }()
                    Text("row \(id) w=\(width)")
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
        #expect(box.widths.contains(80), "never built at viewport width: \(box.widths)")
        // No "garbage width" churn: after settling, no build should use width 1.
        let lastThree = Array(box.widths.suffix(3))
        #expect(
            lastThree.allSatisfy { $0 == 80 },
            "layout must settle on width 80, got \(box.widths)"
        )
    }
}
