import Foundation
import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct ProbeTests {
    @Test func probeNavStackChatLikeSelectable() async throws {
        struct Root: View {
            @State var draft = ""
            var body: some View {
                GeometryReader { _ in
                    NavigationStack {
                        VStack(spacing: 0) {
                            GeometryReader { size in
                                ScrollView {
                                    LazyVStack(alignment: .leading) {
                                        ForEach(0 ..< 8, id: \.self) { i in
                                            Text("目前项目是一个微型分布式节点 \(i) w\(size.widthInt)")
                                        }
                                    }
                                    .selectable()
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                            HStack {
                                Text("测试>")
                                TextEdit(text: $draft)
                            }
                        }
                        .navigationTitle("神衍")
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()
        dumpTree(app.testing_rootElement, depth: 0)

        let selectable = findElement(app.testing_rootElement, name: "SelectableElement")
        print("PROBE2 selectable: \(selectable != nil) frame=\(selectable?.absoluteFrame ?? .zero)")

        let origin = selectable?.absoluteFrame.position ?? .zero
        let press = origin + Position(column: 2, line: 1)
        let leaf = app.testing_rootElement.hitTest(position: press)
        print("PROBE2 hit leaf: \(leaf.map { String(describing: type(of: $0)) } ?? "nil")")
        let target = app.testing_rootElement.pointerGestureTarget(at: press)
        print("PROBE2 gesture target: \(target.map { String(describing: type(of: $0)) } ?? "nil")")

        try await app.testing_turn(input: .mouse(MouseEvent(position: press, type: .pressed(.left))))
        let to = origin + Position(column: 11, line: 2)
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .move)))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .released(.left))))

        if let sel = selectable as? SelectableElement {
            print("PROBE2 hasSelection: \(sel.hasSelection)")
            let text = sel.selectedText() ?? "nil"
            print("PROBE2 selectedText: \(text.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        #expect(true)
    }

    @Test func probeLazyScrollSelectable() async throws {
        struct Root: View {
            var body: some View {
                GeometryReader { size in
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(0 ..< 30, id: \.self) { i in
                                Text("row \(i) width \(size.widthInt)")
                            }
                        }
                        .selectable()
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare()

        dumpTree(app.testing_rootElement, depth: 0)

        let selectable = findElement(app.testing_rootElement, name: "SelectableElement")
        print("PROBE selectable found: \(selectable != nil)")
        if let selectable {
            print("PROBE selectable frame: \(selectable.absoluteFrame)")
        }

        // What does a press at (2, 2) resolve to?
        let pos = Position(column: 2, line: 2)
        let leaf = app.testing_rootElement.hitTest(position: pos)
        print("PROBE hit leaf: \(leaf.map { String(describing: type(of: $0)) } ?? "nil")")
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        print("PROBE gesture target: \(target.map { String(describing: type(of: $0)) } ?? "nil")")

        // Drag from (2,2) to (10,4).
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: Position(column: 10, line: 4), type: .move)))
        try await app.testing_turn(input: .mouse(MouseEvent(position: Position(column: 10, line: 4), type: .released(.left))))

        if let sel = selectable as? SelectableElement {
            print("PROBE hasSelection: \(sel.hasSelection)")
            print("PROBE normalized: \(String(describing: sel.normalizedSelection))")
            let text = sel.selectedText() ?? "nil"
            print("PROBE selectedText: \(text.replacingOccurrences(of: "\n", with: "\\n"))")
        }

        // Re-run the highlight pass manually on a fresh full-window buffer.
        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)
        app.window.selectionCoordinator.applyHighlight(into: &buffer)
        if let sel = selectable as? SelectableElement {
            let text = sel.selectedText() ?? "nil"
            print("PROBE selectedText after manual pass: \(text.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        for line in 0 ..< 6 {
            var row = ""
            for col in 0 ..< 20 {
                row.append(buffer.character(at: Position(column: Extended(col), line: Extended(line))) ?? "·")
            }
            print("PROBE screen row \(line): \(row)")
        }
        #expect(true)
    }
}

@MainActor
private func dumpTree(_ element: Element, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    print("PROBE-TREE \(indent)\(type(of: element)) frame=\(element.layer.frame)")
    guard depth < 8 else { return }
    for child in element.children {
        dumpTree(child, depth: depth + 1)
    }
}

@MainActor
private func findElement(_ element: Element, name: String) -> Element? {
    if String(describing: type(of: element)).contains(name) { return element }
    for child in element.children {
        if let found = findElement(child, name: name) { return found }
    }
    return nil
}
