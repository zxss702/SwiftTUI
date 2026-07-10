import Foundation

/// 对齐 SwiftUI.ButtonRole（告警 / 确认按钮语义）。
@MainActor public struct ButtonRole: Equatable, Sendable {
    let id: String

    public static let cancel = ButtonRole(id: "cancel")
    public static let destructive = ButtonRole(id: "destructive")
}

public extension Button where Label == AnyView {
    /// `Button("取消", role: .cancel) { … }`
    /// Alert / confirmationDialog：文案默认加粗；destructive 为红色。
    init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        let labeled: AnyView
        switch role {
        case .some(let r) where r == .destructive:
            labeled = AnyView(Text(title).bold().foregroundColor(.red))
        default:
            labeled = AnyView(Text(title).bold())
        }
        self.label = VStack(content: labeled)
        self.action = action
        self.hover = {}
    }

    /// 默认中文文案：`nil` → 确定，`.cancel` → 取消，`.destructive` → 删除。
    init(role: ButtonRole?, action: @escaping () -> Void) {
        let title: String
        switch role {
        case .some(let r) where r == .cancel:
            title = "取消"
        case .some(let r) where r == .destructive:
            title = "删除"
        default:
            title = "确定"
        }
        self.init(title, role: role, action: action)
    }
}
