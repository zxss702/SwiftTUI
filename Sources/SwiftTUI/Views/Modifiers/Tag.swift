import Foundation

// MARK: - Public tag

public extension View {
    /// 为视图关联一个可哈希标签，供 `Picker` 等容器识别选项。
    ///
    /// 标签存在环境中（`viewTag`），不绑定到特定容器，便于后续 `List` / `TabView` 等复用。
    func tag<V: Hashable>(_ tag: V, includeOptional: Bool = true) -> some View {
        // includeOptional 预留与 SwiftUICore 对齐（Optional 标签展开），当前始终写入 tag。
        _ = includeOptional
        return TaggedView(tag: AnyHashable(tag), content: self)
    }
}

// MARK: - Environment

private struct ViewTagEnvironmentKey: EnvironmentKey {
    static var defaultValue: AnyHashable? { nil }
}

extension EnvironmentValues {
    /// 当前视图子树上最近的 `.tag` 值；无 tag 时为 `nil`。
    public var viewTag: AnyHashable? {
        get { self[ViewTagEnvironmentKey.self] }
        set { self[ViewTagEnvironmentKey.self] = newValue }
    }
}

// MARK: - Picker interaction

struct PickerSelectAction {
    let action: (AnyHashable) -> Void
    func callAsFunction(_ tag: AnyHashable) { action(tag) }
}

enum PickerOptionChrome: Equatable {
    /// 菜单弹出项：无指示器
    case plain
    /// inline：选中前缀 ✓
    case checkmark
    /// radioGroup：○ / ●
    case radio
    /// segmented：选中项 background + 对比前景色
    case segmented
}

private struct PickerSelectActionKey: EnvironmentKey {
    static var defaultValue: PickerSelectAction? { nil }
}

private struct PickerSelectedTagKey: EnvironmentKey {
    static var defaultValue: AnyHashable? { nil }
}

private struct PickerOptionChromeKey: EnvironmentKey {
    static var defaultValue: PickerOptionChrome { .plain }
}

extension EnvironmentValues {
    var pickerSelectAction: PickerSelectAction? {
        get { self[PickerSelectActionKey.self] }
        set { self[PickerSelectActionKey.self] = newValue }
    }

    var pickerSelectedTag: AnyHashable? {
        get { self[PickerSelectedTagKey.self] }
        set { self[PickerSelectedTagKey.self] = newValue }
    }

    var pickerOptionChrome: PickerOptionChrome {
        get { self[PickerOptionChromeKey.self] }
        set { self[PickerOptionChromeKey.self] = newValue }
    }
}

// MARK: - TaggedView

@MainActor
private struct TaggedView<Content: View>: View {
    let tag: AnyHashable
    let content: Content

    @Environment(\.pickerSelectAction) private var selectAction
    @Environment(\.pickerSelectedTag) private var selectedTag
    @Environment(\.pickerOptionChrome) private var chrome
    @Environment(\.foregroundColor) private var foregroundColor

    var body: some View {
        let tagged = content.environment(\.viewTag, tag)

        if let selectAction {
            let isSelected = selectedTag == tag
            Button {
                selectAction(tag)
            } label: {
                optionLabel(tagged: tagged, isSelected: isSelected)
            }
        } else {
            tagged
        }
    }

    @ViewBuilder
    private func optionLabel(tagged: some View, isSelected: Bool) -> some View {
        switch chrome {
        case .plain:
            tagged
        case .checkmark:
            HStack(spacing: 0) {
                if isSelected { Text("✓ ") }
                tagged
            }
        case .radio:
            HStack(spacing: 0) {
                Text(isSelected ? "● " : "○ ")
                tagged
            }
        case .segmented:
            // 纯 View：选中用主色作背景，文字用对比色
            if isSelected {
                tagged
                    .foregroundColor(segmentedSelectedForeground)
                    .background(segmentedSelectedBackground)
            } else {
                tagged
            }
        }
    }

    /// 选中背景：跟当前文字主色走（default → 黑底，保证浅色终端可见）
    private var segmentedSelectedBackground: Color {
        foregroundColor == .default ? .black : foregroundColor
    }

    private var segmentedSelectedForeground: Color {
        foregroundColor == .default ? .white : .black
    }
}
