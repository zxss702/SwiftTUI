import Foundation

/// 密码输入；显示为 `•`，行为同 TextField（同样响应 `.textFieldStyle`）。
@MainActor
public struct SecureField: View {
    private let title: String
    private let text: Binding<String>

    @Environment(\.textFieldStyleKind) private var styleKind

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    public init(text: Binding<String>, prompt: String? = nil) {
        self.title = prompt ?? ""
        self.text = text
    }

    public var body: some View {
        // 复用 TextField 的样式包装：先建一个带 secure 的核心不可见，
        // 这里直接按 style 包边框 + SecureFieldCore。
        let core = SecureFieldCore(title: title, text: text)
        switch styleKind {
        case .roundedBorder:
            core.border(style: .rounded)
        case .squareBorder:
            core.border(style: .default)
        case .automatic, .plain:
            core
        }
    }
}

@MainActor
private struct SecureFieldCore: View, PrimitiveView {
    let title: String
    let text: Binding<String>

    @Environment(\.placeholderColor) private var placeholderColor: Color
    @Environment(\.multilineTextAlignment) private var alignment: TextAlignment
    @Environment(\.submitAction) private var submitAction: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        let control = TextFieldControl(
            text: text,
            placeholder: title,
            placeholderColor: placeholderColor,
            alignment: alignment,
            isEnabled: isEnabled,
            submitAction: submitAction,
            legacyAction: nil
        )
        control.secure = true
        node.control = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextFieldControl
        control.text = text
        control.placeholder = title
        control.placeholderColor = placeholderColor
        control.alignment = alignment
        control.isEnabledFlag = isEnabled
        control.submitAction = submitAction
        control.secure = true
        control.syncFromBinding()
        control.layer.invalidate()
    }
}
