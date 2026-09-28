import Foundation
import Testing
@testable import SwiftTUI

/// Sheet 是模态层：滚轮落在遮罩/面板非滚动区/内层滚到底之后都必须被吞掉，
/// 不能穿透到 sheet 底下的主界面 ScrollView。回归：`SheetPanel` 曾把整个
/// NavigationStack（含标题栏/工具栏）包进外层 ScrollView —— 滚动会拖着
/// toolbar 一起走且看不到底；修复后 sheet 内容自己管滚动，模态层兜底吞事件。
@Suite(.serialized)
@MainActor
struct SheetScrollIsolationTests {

    private struct Root: View {
        @State var show = false
        var body: some View {
            VStack(spacing: 0) {
                Button("open") { show = true }
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(0..<40, id: \.self) { i in
                            Text("main row \(i)")
                        }
                    }
                }
            }
            .sheet(isPresented: $show) {
                VStack(spacing: 0) {
                    Text("设置")
                        .bold()
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(0..<30, id: \.self) { i in
                                Text("sheet row \(i)")
                            }
                        }
                    }
                }
                .frame(width: 30)
            }
        }
    }

    private func scrollElements(under control: Element?) -> [Element] {
        guard let control else { return [] }
        var found: [Element] = []
        if String(describing: type(of: control)).contains("ScrollElement") {
            found.append(control)
        }
        for child in control.children {
            found.append(contentsOf: scrollElements(under: child))
        }
        return found
    }

    @Test func wheelOverSheetDoesNotScrollUnderlying() async throws {
        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: Size(width: 44, height: 14))

        let open = try #require(findOpenButton(in: app.testing_rootElement))
        app.window.setFirstResponder(open)
        let openPos = center(of: open)
        try await app.testing_turn(input: .mouse(MouseEvent(position: openPos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: openPos, type: .released(.left))))
        #expect(app.window.popupPresenter?.isPresented == true, "sheet should be open")

        let host = try #require(app.window.popupPresenter?.top?.hostElement)
        let scrolls = scrollElements(under: app.testing_rootElement)
        let main = try #require(scrolls.first(where: { !$0.isDescendant(of: host) }))
        let inner = try #require(scrolls.first(where: { $0.isDescendant(of: host) && $0 !== main }))
        let mainContent = try #require(main.children.first)

        // 1) 滚轮落在遮罩上 —— 不得穿透到底下的主界面
        let scrimPos = Position(column: 1, line: 1)
        let baseline = mainContent.absoluteFrame.position.line
        app.handleTerminalEvent(.mouse(MouseEvent(position: scrimPos, type: .scroll(deltaX: 0, deltaY: 5))))
        _ = try await app.settleHost()
        #expect(mainContent.absoluteFrame.position.line == baseline,
                "滚轮落在遮罩上却滚动了主界面 (baseline=\(baseline) after=\(mainContent.absoluteFrame.position.line))")

        // 2) 滚轮落在 sheet 内层滚动区 —— 内层滚动，主界面不动
        let innerPos = center(of: inner)
        let innerContent = try #require(inner.children.first)
        let innerBaseline = innerContent.absoluteFrame.position.line
        app.handleTerminalEvent(.mouse(MouseEvent(position: innerPos, type: .scroll(deltaX: 0, deltaY: 3))))
        _ = try await app.settleHost()
        #expect(innerContent.absoluteFrame.position.line < innerBaseline,
                "sheet 内层没滚动 (baseline=\(innerBaseline) after=\(innerContent.absoluteFrame.position.line))")
        #expect(mainContent.absoluteFrame.position.line == baseline,
                "sheet 内层滚动带动了主界面")

        // 3) 内层滚到底后继续滚 —— 仍不得穿透到主界面
        for _ in 0..<20 {
            app.handleTerminalEvent(.mouse(MouseEvent(position: innerPos, type: .scroll(deltaX: 0, deltaY: 10))))
            _ = try await app.settleHost()
        }
        #expect(mainContent.absoluteFrame.position.line == baseline,
                "内层滚到底后滚轮穿透到主界面 (baseline=\(baseline) after=\(mainContent.absoluteFrame.position.line))")
    }

    private func findOpenButton(in control: Element?) -> Element? {
        guard let control else { return nil }
        if String(describing: type(of: control)).contains("Button"),
           sheetTextLabel(in: control) == "open" {
            return control
        }
        for child in control.children {
            if let found = findOpenButton(in: child) { return found }
        }
        return nil
    }

    private func sheetTextLabel(in control: Element) -> String? {
        if let text = Mirror(reflecting: control).children
            .first(where: { $0.label == "text" })?.value as? String {
            return text
        }
        for child in control.children {
            if let text = sheetTextLabel(in: child) { return text }
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
}
