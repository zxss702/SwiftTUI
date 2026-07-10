import Foundation

// MARK: - Protocol

/// Picker 外观协议。新增内置样式时增加 conformer + 静态访问器即可。
@MainActor public protocol PickerStyle {}

// MARK: - Built-in styles

@MainActor public struct DefaultPickerStyle: PickerStyle {
    public init() {}
}

@MainActor public struct MenuPickerStyle: PickerStyle {
    public init() {}
}

@MainActor public struct InlinePickerStyle: PickerStyle {
    public init() {}
}

@MainActor public struct RadioGroupPickerStyle: PickerStyle {
    public init() {}
}

@MainActor public struct SegmentedPickerStyle: PickerStyle {
    public init() {}
}

// MARK: - Static accessors

extension PickerStyle where Self == DefaultPickerStyle {
    public static var automatic: DefaultPickerStyle { DefaultPickerStyle() }
}

extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}

extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

extension PickerStyle where Self == RadioGroupPickerStyle {
    public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() }
}

extension PickerStyle where Self == SegmentedPickerStyle {
    public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() }
}

// MARK: - Resolved kind（内部）

enum PickerStyleKind: Equatable {
    case automatic
    case menu
    case inline
    case radioGroup
    case segmented
}

@MainActor
protocol _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { get }
}

extension DefaultPickerStyle: _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { .automatic }
}

extension MenuPickerStyle: _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { .menu }
}

extension InlinePickerStyle: _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { .inline }
}

extension RadioGroupPickerStyle: _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { .radioGroup }
}

extension SegmentedPickerStyle: _PickerStyleResolvable {
    var pickerStyleKind: PickerStyleKind { .segmented }
}

// MARK: - Environment + modifier

private struct PickerStyleKindEnvironmentKey: EnvironmentKey {
    static var defaultValue: PickerStyleKind { .automatic }
}

extension EnvironmentValues {
    var pickerStyleKind: PickerStyleKind {
        get { self[PickerStyleKindEnvironmentKey.self] }
        set { self[PickerStyleKindEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        let kind = (style as? any _PickerStyleResolvable)?.pickerStyleKind ?? .automatic
        return environment(\.pickerStyleKind, kind)
    }
}
