import Foundation

// MARK: - DismissAction

/// 类似 SwiftUI 的 DismissAction，在 TUI 最顶层相当于正常退出应用。
/// 它会走完完整的退出流程（关闭鼠标、恢复终端、退出备用缓冲区等），
/// 并结束 `Application.start()` 的执行，而不是强制 kill 进程。
@MainActor
public struct DismissAction {
    let action: @MainActor () -> Void

    public func callAsFunction() {
        action()
    }
}

// MARK: - EnvironmentKey

struct DismissActionKey: EnvironmentKey {
    @MainActor static let defaultValue: DismissAction = DismissAction(action: {
        // 默认无操作（未挂载到 Application 前）
    })
}

/// Alert / Menu 内按钮点击后是否自动 dismiss 当前 present。
struct ButtonDismissesPresentationKey: EnvironmentKey {
    @MainActor static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }

    var buttonDismissesPresentation: Bool {
        get { self[ButtonDismissesPresentationKey.self] }
        set { self[ButtonDismissesPresentationKey.self] = newValue }
    }
}
