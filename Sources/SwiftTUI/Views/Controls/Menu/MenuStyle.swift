import Foundation

// MARK: - Protocol

/// Menu 外观协议。新增样式时增加 conformer + 静态访问器即可。
@MainActor public protocol MenuStyle {}

// MARK: - Built-in styles

@MainActor public struct DefaultMenuStyle: MenuStyle {
    public init() {}
}

@MainActor public struct BorderlessButtonMenuStyle: MenuStyle {
    public init() {}
}

@MainActor public struct BorderedButtonMenuStyle: MenuStyle {
    public init() {}
}

@MainActor public struct ButtonMenuStyle: MenuStyle {
    public init() {}
}

// MARK: - Static accessors

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == BorderlessButtonMenuStyle {
    public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

extension MenuStyle where Self == BorderedButtonMenuStyle {
    public static var borderedButton: BorderedButtonMenuStyle { BorderedButtonMenuStyle() }
}

extension MenuStyle where Self == ButtonMenuStyle {
    public static var button: ButtonMenuStyle { ButtonMenuStyle() }
}

// MARK: - Resolved kind（内部）

enum MenuStyleKind: Equatable {
    case automatic
    case borderlessButton
    case borderedButton
    case button
}

@MainActor
protocol _MenuStyleResolvable {
    var menuStyleKind: MenuStyleKind { get }
}

extension DefaultMenuStyle: _MenuStyleResolvable {
    var menuStyleKind: MenuStyleKind { .automatic }
}

extension BorderlessButtonMenuStyle: _MenuStyleResolvable {
    var menuStyleKind: MenuStyleKind { .automatic }
}

extension BorderedButtonMenuStyle: _MenuStyleResolvable {
    var menuStyleKind: MenuStyleKind { .borderedButton }
}

extension ButtonMenuStyle: _MenuStyleResolvable {
    var menuStyleKind: MenuStyleKind { .button }
}

// MARK: - Environment + modifier

private struct MenuStyleKindEnvironmentKey: EnvironmentKey {
    static var defaultValue: MenuStyleKind { .automatic }
}

extension EnvironmentValues {
    var menuStyleKind: MenuStyleKind {
        get { self[MenuStyleKindEnvironmentKey.self] }
        set { self[MenuStyleKindEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func menuStyle<S: MenuStyle>(_ style: S) -> some View {
        let kind = (style as? any _MenuStyleResolvable)?.menuStyleKind ?? .automatic
        return environment(\.menuStyleKind, kind)
    }
}
