import Foundation

// MARK: - Protocol

/// Toggle 外观协议。新增内置样式时增加 conformer + 静态访问器即可。
@MainActor public protocol ToggleStyle {}

// MARK: - Built-in styles

@MainActor public struct DefaultToggleStyle: ToggleStyle {
    public init() {}
}

@MainActor public struct CheckboxToggleStyle: ToggleStyle {
    public init() {}
}

@MainActor public struct SwitchToggleStyle: ToggleStyle {
    public init() {}
}

@MainActor public struct ButtonToggleStyle: ToggleStyle {
    public init() {}
}

// MARK: - Static accessors

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

extension ToggleStyle where Self == ButtonToggleStyle {
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

// MARK: - Resolved kind（内部）

enum ToggleStyleKind: Equatable {
    case automatic
    case checkbox
    case `switch`
    case button
}

@MainActor
protocol _ToggleStyleResolvable {
    var toggleStyleKind: ToggleStyleKind { get }
}

extension DefaultToggleStyle: _ToggleStyleResolvable {
    var toggleStyleKind: ToggleStyleKind { .automatic }
}

extension CheckboxToggleStyle: _ToggleStyleResolvable {
    var toggleStyleKind: ToggleStyleKind { .checkbox }
}

extension SwitchToggleStyle: _ToggleStyleResolvable {
    var toggleStyleKind: ToggleStyleKind { .switch }
}

extension ButtonToggleStyle: _ToggleStyleResolvable {
    var toggleStyleKind: ToggleStyleKind { .button }
}

// MARK: - Environment + modifier

private struct ToggleStyleKindEnvironmentKey: EnvironmentKey {
    static var defaultValue: ToggleStyleKind { .automatic }
}

extension EnvironmentValues {
    var toggleStyleKind: ToggleStyleKind {
        get { self[ToggleStyleKindEnvironmentKey.self] }
        set { self[ToggleStyleKindEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        let kind = (style as? any _ToggleStyleResolvable)?.toggleStyleKind ?? .automatic
        return environment(\.toggleStyleKind, kind)
    }
}
