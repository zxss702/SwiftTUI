import SwiftTUI

/// 演示 macOS 现行 `TextFieldStyle`：automatic / plain / roundedBorder / squareBorder。
struct TextFieldStyleExampleApp: View {
    @State private var automatic = ""
    @State private var plain = ""
    @State private var rounded = ""
    @State private var square = ""
    @State private var password = ""
    @State private var status = "Ready"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                header
                styles
                secure
                Text("Ctrl+C 退出").foregroundColor(.brightBlack)
            }
            .padding(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TextFieldStyle").bold()
            Text(".textFieldStyle — automatic / plain / roundedBorder / squareBorder")
                .foregroundColor(.brightBlack)
            Text(status).foregroundColor(.cyan)
            Divider()
        }
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("automatic（默认，无装饰）").bold()
            TextField("automatic", text: $automatic)
                .textFieldStyle(.automatic)
                .onSubmit { status = "automatic: \(automatic)" }

            Text("plain").bold()
            TextField("plain", text: $plain)
                .textFieldStyle(.plain)

            Text("roundedBorder").bold()
            TextField("roundedBorder", text: $rounded)
                .textFieldStyle(.roundedBorder)

            Text("squareBorder").bold()
            TextField("squareBorder", text: $square)
                .textFieldStyle(.squareBorder)
            Divider()
        }
    }

    private var secure: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("SecureField + roundedBorder").bold()
            SecureField("密码（末字短暂明文）", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("password •=\(String(repeating: "•", count: password.count))")
                .foregroundColor(.brightBlack)
        }
    }
}

try await Application(rootView: TextFieldStyleExampleApp()).start()
