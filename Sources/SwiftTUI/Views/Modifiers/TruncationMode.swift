import Foundation

extension Text {
    /// 文本超出可用空间时省略号的位置，对齐 SwiftUI `Text.TruncationMode`。
    public enum TruncationMode: Hashable, Sendable {
        /// 省略开头：`…text`
        case head
        /// 省略中间：`te…xt`
        case middle
        /// 省略结尾：`text…`（默认）
        case tail
    }
}

public extension View {
    func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }
}

private struct TruncationModeEnvironmentKey: EnvironmentKey {
    static var defaultValue: Text.TruncationMode { .tail }
}

extension EnvironmentValues {
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeEnvironmentKey.self] }
        set { self[TruncationModeEnvironmentKey.self] = newValue }
    }
}
