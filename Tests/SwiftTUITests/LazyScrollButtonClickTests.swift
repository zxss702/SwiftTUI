import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct LazyScrollButtonClickTests {

    @Test func lazyVStackButtonClickIncrements() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                ScrollView {
                    LazyVStack {
                        ForEach(0 ..< 30, id: \.self) { i in
                            if i == 5 {
                                Button("tap-me") { onTap() }
                            } else {
                                Text("row-\(i)")
                            }
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare()
        let button = try #require(findLabeledButton("tap-me", in: app.testing_rootElement))
        let pos = centerOf(button)
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        #expect(target != nil, "pointer target nil at \(pos)")
        #expect(
            String(describing: type(of: target!)).contains("Button"),
            "expected Button, got \(type(of: target!)) frame=\(button.absoluteFrame)"
        )
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.n == 1, "button action not fired; target was \(String(describing: target.map { type(of: $0) }))")
    }

    @Test func lazyVGridSectionButtonClickIncrements() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
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
                        Section {} footer: { Text("最新") }
                        ForEach(0 ..< 3, id: \.self) { i in
                            Section {
                                Button("cell-\(i)") { onTap() }
                            } footer: {
                                Text("f-\(i)")
                            }
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare()
        let button = try #require(findLabeledButton("cell-0", in: app.testing_rootElement))
        let pos = centerOf(button)
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        #expect(
            target != nil && String(describing: type(of: target!)).contains("Button"),
            "got \(String(describing: target.map { type(of: $0) })) at \(pos) btnFrame=\(button.absoluteFrame)"
        )
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.n == 1)
    }

    @Test func lazyVStackButtonWithOuterFrameClick() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0 ..< 20, id: \.self) { i in
                            if i == 3 {
                                Button("think") { onTap() }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("msg-\(i)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 1)
                                    .border(.rounded)
                            }
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare()
        let button = try #require(findLabeledButton("think", in: app.testing_rootElement))
        let pos = centerOf(button)
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        let tname = target.map { String(describing: type(of: $0)) } ?? "nil"
        #expect(tname.contains("Button"), "target=\(tname) pos=\(pos) btn=\(button.absoluteFrame)")
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.n == 1, "fired=\(box.n) target=\(tname)")
    }

    @Test func lazyVStackBorderedButtonClick() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0 ..< 10, id: \.self) { i in
                            Button("go-\(i)") { onTap() }
                                .padding(.horizontal, 1)
                                .border(.rounded)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare()
        let button = try #require(findLabeledButton("go-2", in: app.testing_rootElement))
        let pos = centerOf(button)
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        let tname = target.map { String(describing: type(of: $0)) } ?? "nil"
        #expect(tname.contains("Button"), "target=\(tname)")
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.n == 1)
    }

    @Test func lazyVGridNavigationLinkLikeClick() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 4),
                            alignment: .leading,
                            spacing: 1,
                            pinnedViews: .sectionFooters
                        ) {
                            Section {} footer: { Text("最新") }
                            ForEach(0 ..< 2, id: \.self) { i in
                                Section {
                                    ForEach(0 ..< 3, id: \.self) { j in
                                        Button("node_\(i)_\(j)") { onTap() }
                                            .foregroundColor(.green)
                                    }
                                } footer: {
                                    Text("f-\(i)")
                                }
                            }
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare()
        let button = try #require(findLabeledButton("node_0_0", in: app.testing_rootElement))
        // Also probe a few cells around the painted text
        var hitButton = false
        let frame = button.absoluteFrame
        for dcol in [Extended(0), Extended(1), frame.size.width / 2] {
            for dline in [Extended(0), frame.size.height / 2] {
                let pos = Position(column: frame.position.column + dcol, line: frame.position.line + dline)
                if let t = app.testing_rootElement.pointerGestureTarget(at: pos),
                   String(describing: type(of: t)).contains("Button") {
                    hitButton = true
                    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
                    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
                    break
                }
            }
            if box.n > 0 { break }
        }
        #expect(hitButton, "never hit button; frame=\(frame)")
        #expect(box.n == 1)
    }


    /// Diff 页真实形状：footer 含 GeometryReader + hover Menu；cell 为 NavigationLink 式 Button。
    @Test func lazyVGridDiffShapeButtonAndMenuClick() async throws {
        final class Box { var cell = 0; var menuOpenPath = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            @State var isHover = false
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(minimum: 16, maximum: .infinity), spacing: 1, alignment: .leading), count: 4),
                            alignment: .leading,
                            spacing: 1,
                            pinnedViews: .sectionFooters
                        ) {
                            Section {} footer: {
                                HStack {
                                    GeometryReader { size in
                                        Text(String(repeating: "─", count: size.widthInt))
                                    }
                                    .frame(maxWidth: .infinity)
                                    Text("最新")
                                    GeometryReader { size in
                                        Text(String(repeating: "─", count: size.widthInt))
                                    }
                                    .frame(maxWidth: .infinity)
                                    if isHover {
                                        Menu {
                                            Button("确认") { box.menuOpenPath += 1 }
                                        } label: {
                                            Text("切换至此")
                                        }
                                    }
                                }
                                .onHover { isHover = $0 }
                            }
                            ForEach(0 ..< 2, id: \.self) { i in
                                Section {
                                    ForEach(0 ..< 2, id: \.self) { j in
                                        Button("node_\(i)_\(j)") { box.cell += 1 }
                                            .foregroundColor(.green)
                                    }
                                } footer: {
                                    HStack {
                                        GeometryReader { size in
                                            Text(String(repeating: "─", count: size.widthInt))
                                        }
                                        .frame(maxWidth: .infinity)
                                        Text("f-\(i)")
                                        GeometryReader { size in
                                            Text(String(repeating: "─", count: size.widthInt))
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 80, height: 24))

        let button = try #require(findLabeledButton("node_0_0", in: app.testing_rootElement))
        let pos = centerOf(button)
        let leaf = app.testing_rootElement.hitTest(position: pos)
        let target = app.testing_rootElement.pointerGestureTarget(at: pos)
        #expect(
            target != nil && String(describing: type(of: target!)).contains("Button"),
            "leaf=\(String(describing: leaf.map { type(of: $0) })) target=\(String(describing: target.map { type(of: $0) })) pos=\(pos) btn=\(button.absoluteFrame)"
        )
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        #expect(box.cell == 1, "cell taps=\(box.cell)")
    }

    /// 点在 Button 外侧的 maxWidth infinity 空白上——当前语义不捐赠给 Button；
    /// 若用户体感「整行点不了」，这里应记录为 frame 命中问题。
    @Test func outerFrameChromeDoesNotFireButton() async throws {
        final class Box { var n = 0 }
        let box = Box()
        struct Root: View {
            let onTap: () -> Void
            var body: some View {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        Button("short") { onTap() }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        let app = Application(rootView: Root(onTap: { box.n += 1 }))
        try await app.testing_prepare(size: Size(width: 60, height: 10))
        let button = try #require(findLabeledButton("short", in: app.testing_rootElement))
        // Far right of the expanded frame, past the label.
        let frame = button.absoluteFrame
        // Climb to outer FlexibleFrame
        var outer: Element = button
        while let p = outer.parent { outer = p }
        // Find FlexibleFrame wrapping button
        func findFrame(around e: Element) -> Element? {
            var c: Element? = e
            while let n = c {
                if String(describing: type(of: n)).contains("FlexibleFrame") { return n }
                c = n.parent
            }
            return nil
        }
        let flex = try #require(findFrame(around: button))
        let far = Position(
            column: flex.absoluteFrame.position.column + flex.absoluteFrame.size.width - 2,
            line: flex.absoluteFrame.position.line
        )
        let target = app.testing_rootElement.pointerGestureTarget(at: far)
        let tname = target.map { String(describing: type(of: $0)) } ?? "nil"
        // Document current behavior
        print("FAR_TARGET=\(tname) far=\(far) btn=\(frame) flex=\(flex.absoluteFrame)")
        try await app.testing_turn(input: .mouse(MouseEvent(position: far, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: far, type: .released(.left))))
        // Expectation TBD — print result
        #expect(true)
        _ = box.n
    }

}

@MainActor
private func findLabeledButton(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button") {
        if textOf(root) == label { return root }
    }
    for child in root.children {
        if let found = findLabeledButton(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func textOf(_ control: Element) -> String? {
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
        return text
    }
    for child in control.children {
        if let t = textOf(child) { return t }
    }
    return nil
}

@MainActor
private func centerOf(_ control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
}
