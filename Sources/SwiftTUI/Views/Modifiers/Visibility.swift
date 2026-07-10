import Foundation

/// 控制指示器等元素是否可见，对齐 SwiftUI.Visibility。
@MainActor public enum Visibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
}

// MARK: - labelsHidden

public extension View {
    /// 隐藏控件标签（如 Picker 的标题）。
    func labelsHidden() -> some View {
        environment(\.labelsHidden, true)
    }
}

private struct LabelsHiddenEnvironmentKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var labelsHidden: Bool {
        get { self[LabelsHiddenEnvironmentKey.self] }
        set { self[LabelsHiddenEnvironmentKey.self] = newValue }
    }
}

// MARK: - menuIndicator

public extension View {
    /// 控制 Menu 下拉指示器的可见性。
    func menuIndicator(_ visibility: Visibility) -> some View {
        environment(\.menuIndicatorVisibility, visibility)
    }
}

private struct MenuIndicatorVisibilityEnvironmentKey: EnvironmentKey {
    static var defaultValue: Visibility { .automatic }
}

extension EnvironmentValues {
    var menuIndicatorVisibility: Visibility {
        get { self[MenuIndicatorVisibilityEnvironmentKey.self] }
        set { self[MenuIndicatorVisibilityEnvironmentKey.self] = newValue }
    }
}

// MARK: - horizontalRadioGroupLayout

public extension View {
    /// 让 `.radioGroup` 风格的 Picker 水平排列选项。
    func horizontalRadioGroupLayout() -> some View {
        environment(\.horizontalRadioGroupLayout, true)
    }
}

private struct HorizontalRadioGroupLayoutEnvironmentKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var horizontalRadioGroupLayout: Bool {
        get { self[HorizontalRadioGroupLayoutEnvironmentKey.self] }
        set { self[HorizontalRadioGroupLayoutEnvironmentKey.self] = newValue }
    }
}
