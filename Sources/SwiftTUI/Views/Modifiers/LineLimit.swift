import Foundation

public extension View {
    /// 限制文本最大行数。`nil` 表示不限制（对齐 SwiftUI）。
    ///
    /// 超出时按 `truncationMode` 显示省略号 `…`。
    func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, number)
    }
}

private struct LineLimitEnvironmentKey: EnvironmentKey {
    static var defaultValue: Int? { nil }
}

extension EnvironmentValues {
    public var lineLimit: Int? {
        get { self[LineLimitEnvironmentKey.self] }
        set { self[LineLimitEnvironmentKey.self] = newValue }
    }
}
