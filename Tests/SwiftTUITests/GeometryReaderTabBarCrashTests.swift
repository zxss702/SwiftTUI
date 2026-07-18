import Testing
@testable import SwiftTUI

/// 回归：GeometryReader 测宽时 HStack 内 `if` 箭头 + ForEach 标签同时变，
/// 不得因 Optional.removeElement 与惰性 ForEach 错位而崩溃（Logorythia「更多」）。
@Suite(.serialized)
@MainActor
struct GeometryReaderTabBarCrashTests {
    @Test func geometryReaderHStackOptionalForEachSettles() async throws {
        struct Root: View {
            @State var wide = false
            var body: some View {
                VStack {
                    Button("toggle") { wide.toggle() }
                    GeometryReader { size in
                        let w = size.widthInt
                        let showLeft = w > 20
                        let showRight = w > 20
                        let count = w > 40 ? 6 : 2
                        HStack(spacing: 1) {
                            if showLeft {
                                Text("<")
                            }
                            ForEach(0 ..< count, id: \.self) { i in
                                Text("t\(i)")
                            }
                            if showRight {
                                Text(">")
                            }
                        }
                    }
                    .frame(width: wide ? 60 : 10, height: 1)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 80, height: 10))

        let toggle = try #require(findButtonLabeled("toggle", in: app.testing_rootElement))
        for _ in 0 ..< 4 {
            try await click(toggle, on: app)
            #expect(!app.hasPendingCommitWork)
        }
        #expect(findText(in: app.testing_rootElement, equalTo: "t0") != nil)
    }

    /// 回归（对齐 SwiftUI）：页面 `@State` 写在 `.toolbar` 里，箭头改 offset 必须刷新 chrome。
    @Test func toolbarPrincipalGeometryReaderStateArrowRefreshes() async throws {
        struct Root: View {
            @State var offset = 0
            let titles = ["A0", "A1", "A2", "A3", "A4", "A5"]
            var body: some View {
                NavigationStack {
                    Text("page")
                        .navigationTitle("t")
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                GeometryReader { _ in
                                    HStack(spacing: 1) {
                                        if offset > 0 {
                                            Button { offset = max(0, offset - 1) } label: { Text("<") }
                                        }
                                        Text(titles[offset])
                                        if offset < titles.count - 1 {
                                            Button {
                                                offset = min(titles.count - 1, offset + 1)
                                            } label: {
                                                Text(">")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 40, height: 8))
        #expect(findText(in: app.testing_rootElement, equalTo: "A0") != nil)

        let right = try #require(findButtonLabeled(">", in: app.testing_rootElement))
        try await click(right, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "A1") != nil)
        #expect(findText(in: app.testing_rootElement, equalTo: "A0") == nil)

        try await click(right, on: app)
        #expect(findText(in: app.testing_rootElement, equalTo: "A2") != nil)
    }
}

@MainActor
private func findButtonLabeled(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"),
       textLabel(in: root) == label
    {
        return root
    }
    for child in root.children {
        if let found = findButtonLabeled(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func textLabel(in control: Element) -> String? {
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
        return text
    }
    for child in control.children {
        if let text = textLabel(in: child) { return text }
    }
    return nil
}

@MainActor
private func findText(in control: Element?, equalTo value: String) -> Element? {
    guard let control else { return nil }
    if textLabel(in: control) == value { return control }
    for child in control.children {
        if let found = findText(in: child, equalTo: value) { return found }
    }
    return nil
}

@MainActor
private func center(of control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
}

@MainActor
private func click(_ button: Element, on app: Application) async throws {
    let pos = center(of: button)
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
}
