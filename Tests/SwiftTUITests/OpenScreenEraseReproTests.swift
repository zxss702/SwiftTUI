import Foundation
import Testing
@testable import SwiftTUI

/// 打开即消失回归：首帧正常，随后某个刷新把已画好的字符抹掉。
/// 用物理屏模拟器对比 back buffer —— "画出后被擦除"必表现为两者发散。
@Suite(.serialized)
@MainActor
struct OpenScreenEraseReproTests {
    @Test func welcomeScreenKeepsContentAcrossIdleTurns() async throws {
        let size = Size(width: 60, height: 20)
        struct Root: View {
            @State var text = ""
            @FocusState var focus: Bool
            var body: some View {
                NavigationStack {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                Text("欢迎回来，这里是 Logorythia")
                                ForEach(0..<8, id: \.self) { i in
                                    Text("历史会话 \(i)：新建 hello 文件")
                                }
                            }
                            .padding(.all, 1)
                        }
                        HStack(spacing: 0) {
                            TextEdit(text: $text)
                                .focused($focus)
                                .defaultFocus($focus, true)
                            if text.isEmpty {
                                HStack(spacing: 1) {
                                    Button("发送") {}
                                    Button("暂停") {}
                                }
                            }
                        }
                        .frame(maxHeight: 1)
                    }
                    .navigationTitle("神衍")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("变更") {}
                        }
                    }
                }
            }
        }

        let mock = RecordingTerminal(size: size)
        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size, terminal: mock)

        var screen = PhysicalScreenEmulator(width: size.widthInt, height: size.heightInt)
        let initialOut = await mock.drainOutput()
        print("INIT-OUT:\n\(initialOut.replacingOccurrences(of: "\u{1B}", with: "␛").replacingOccurrences(of: "\u{0000}", with: "·"))")
        screen.feed(initialOut)
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "initial paint")

        // 空闲若干 turn（模拟状态轮询/观察者触发），每帧后物理屏必须仍与 back 一致
        for i in 0 ..< 3 {
            try await app.testing_turn()
            try await app.testing_drainUntilIdle()
            screen.feed(await mock.drainOutput())
            try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "idle turn \(i)")
        }

        // 滚轮一下（用户截图 2 的动作）
        try await app.testing_turn(input: .mouse(MouseEvent(
            position: Position(column: Extended(10), line: Extended(5)),
            type: .scroll(deltaX: 0, deltaY: 3)
        )))
        try await app.testing_drainUntilIdle()
        let scrollOut = await mock.drainOutput()
        screen.feed(scrollOut)
        let escaped = scrollOut
            .replacingOccurrences(of: "\u{1B}", with: "␛")
            .replacingOccurrences(of: "\u{0000}", with: "·")
        print("SCROLL-OUT:\n\(escaped)")
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "after scroll")
    }

    private func expectPhysicalMatchesBackBuffer(
        _ app: Application,
        screen: PhysicalScreenEmulator,
        size: Size,
        _ context: @autoclosure () -> String
    ) throws {
        var mismatches: [String] = []
        for line in 0 ..< size.heightInt {
            for column in 0 ..< size.widthInt {
                let logical = app.testing_vtCharacter(
                    at: Position(column: Extended(column), line: Extended(line))
                ) ?? " "
                let physical = screen.character(atColumn: column + 1, row: line + 1)
                if logical != physical {
                    mismatches.append(
                        "(\(column),\(line)) logical \(String(reflecting: logical)) physical \(String(reflecting: physical))"
                    )
                }
            }
        }
        #expect(
            mismatches.isEmpty,
            "\(context()): physical screen diverged in \(mismatches.count) cells: \(mismatches.prefix(12).joined(separator: ", "))"
        )
    }
}
