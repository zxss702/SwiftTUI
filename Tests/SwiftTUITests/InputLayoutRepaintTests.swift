import Foundation
import Testing
@testable import SwiftTUI

/// 输入区布局换挡重绘：输入首字符后 HStack{发送,暂停} → VStack{发送/暂停}
/// 的条件分支替换必须在同一帧里同时擦掉旧位置、画出新位置。
/// 回归：实测中旧「发送 暂停」水平排残留 + 新垂直排叠印，造成按钮错位重影。
@Suite(.serialized)
@MainActor
struct InputLayoutRepaintTests {
    @Test func controlRowSwapAfterFirstInputLeavesNoStaleGlyphs() async throws {
        struct Root: View {
            @State var text = ""
            @FocusState var isFocus: Bool
            var body: some View {
                VStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 0) {
                        if !text.isEmpty {
                            Divider()
                        }
                        HStack(spacing: 0) {
                            TextEdit(text: $text)
                                .focused($isFocus)
                                .defaultFocus($isFocus, true)

                            if text.isEmpty {
                                HStack(spacing: 1) {
                                    Button("发送") {}
                                    Button("暂停") {}
                                }
                            } else {
                                VStack(spacing: 1) {
                                    Button("发送") {}
                                    Button("暂停") {}
                                }
                                .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .frame(maxHeight: text.isEmpty ? 1 : 6)
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: Size(width: 40, height: 12))

        let editor = try #require(findTextEdit(in: app.testing_rootElement))
        app.window.setFirstResponder(editor)
        try await app.testing_turn()

        // 逐字符输入到换行 —— 分支替换 + maxHeight 换挡 + 编辑器增高，
        // 每个 keystroke 都要求旧位置被擦掉、新位置被画上
        for ch in Array("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") {
            try await app.testing_turn(
                input: .key(KeyEvent(character: ch, keycode: 0, modifiers: [], type: .press))
            )
        }
        try await app.testing_drainUntilIdle()

        // 全屏扫描：「发」「暂」各只能出现一次（宽字符续格读 \u{0000}，不重复计数）
        var rows: [String] = []
        for row in 0 ..< 12 {
            var line = ""
            for column in 0 ..< 40 {
                line.append(app.testing_vtCharacter(at: Position(column: Extended(column), line: Extended(row))) ?? " ")
            }
            rows.append(line.replacingOccurrences(of: "\u{0000}", with: "·"))
        }
        let screen = rows.enumerated().map { "\($0): \($1)" }.joined(separator: "\n")

        var sendPos: Position?
        var pausePos: Position?
        var sendLead = 0
        var pauseLead = 0
        for row in 0 ..< 12 {
            for column in 0 ..< 40 {
                switch app.testing_vtCharacter(at: Position(column: Extended(column), line: Extended(row))) {
                case "发":
                    sendLead += 1
                    sendPos = Position(column: Extended(column), line: Extended(row))
                case "暂":
                    pauseLead += 1
                    pausePos = Position(column: Extended(column), line: Extended(row))
                default: break
                }
            }
        }
        #expect(sendLead == 1, "发送 有 \(sendLead) 处\n\(screen)\n\(dumpFrames(app.testing_rootElement))")
        #expect(pauseLead == 1, "暂停 有 \(pauseLead) 处\n\(screen)\n\(dumpFrames(app.testing_rootElement))")

        // 垂直排：发送应在暂停的上一行同列
        let send = try #require(sendPos)
        let pause = try #require(pausePos)
        #expect(send.line + 2 == pause.line, "发送/暂停 应垂直相邻（间隔 1），got \(send) / \(pause)\n\(screen)")
        #expect(send.column == pause.column)
    }
}

@MainActor private func dumpFrames(_ control: Element, depth: Int = 0) -> String {
    var out = String(repeating: " ", count: depth) + "\(type(of: control)) \(control.layer.frame)\n"
    for child in control.children {
        out += dumpFrames(child, depth: depth + 2)
    }
    return out
}

@MainActor private func findTextEdit(in control: Element?) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains("TextEdit") { return control }
    for child in control.children {
        if let found = findTextEdit(in: child) { return found }
    }
    return nil
}
