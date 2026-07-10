import SwiftTUI

/// 演示 macOS 现行 `TextEditorStyle`：automatic / plain / roundedBorder。
struct TextEditorStyleExampleApp: View {
    @State private var automatic = "automatic：默认外观（TUI 同 plain）"
    @State private var plain = "plain：无装饰\n第二行"
    @State private var rounded = "roundedBorder：圆角边框\n可多行编辑\n滚轮滚动"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                header
                editors
                Text("Ctrl+C 退出").foregroundColor(.brightBlack)
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TextEditorStyle").bold()
            Text(".textEditorStyle — automatic / plain / roundedBorder")
                .foregroundColor(.brightBlack)
            Divider()
        }
    }

    private var editors: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("automatic").bold()
            TextEditor(text: $automatic)
                .textEditorStyle(.automatic)
                .frame(height: 3)

            Text("plain").bold()
            TextEditor(text: $plain)
                .textEditorStyle(.plain)
                .frame(height: 3)

            Text("roundedBorder").bold()
            TextEditor(text: $rounded)
                .textEditorStyle(.roundedBorder)
                .frame(height: 5)

            Text("字数 auto=\(automatic.count) plain=\(plain.count) rounded=\(rounded.count)")
                .foregroundColor(.brightBlack)
        }
    }
}

try await Application(rootView: TextEditorStyleExampleApp()).start()
