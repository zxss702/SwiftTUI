import Testing
@testable import SwiftTUI

/// 回归：惰性 ForEach 打开 Menu 后叠层必须完成布局（非 0×0），否则标题菜单/菜单项无法点击。
@Suite(.serialized)
@MainActor
struct MenuPopupLayoutTests {
    @Test func menuPanelLaysOutAfterOpen() async throws {
        final class Box { var taps = 0 }
        let box = Box()
        struct Root: View {
            let box: Box
            var body: some View {
                Menu("menu") {
                    Button("item") { box.taps += 1 }
                }
            }
        }
        let app = Application(rootView: Root(box: box))
        try await app.testing_prepare(size: Size(width: 40, height: 16))

        let menu = try #require(findLabeledButton("menu", in: app.testing_rootElement))
        try await click(menu, on: app)
        #expect(app.window.popupPresenter?.isPresented == true)

        let item = try #require(findLabeledButton("item", in: app.testing_rootElement))
        let frame = item.absoluteFrame
        #expect(frame.size.width > 0 && frame.size.height > 0, "menu item still 0×0: \(frame)")
        if let panel = app.window.popupPresenter?.panelFrame {
            #expect(panel.size.width > 0 && panel.size.height > 0, "panel still 0×0: \(panel)")
        }

        try await click(item, on: app)
        #expect(box.taps == 1)
    }
}

@MainActor
private func findLabeledButton(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"), textLabel(in: root) == label {
        return root
    }
    for child in root.children {
        if let found = findLabeledButton(label, in: child) { return found }
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
