import Foundation

// MARK: - TextFieldStyle

/// 对齐 SwiftUI.TextFieldStyle（macOS 现行：automatic / plain / roundedBorder / squareBorder）。
@MainActor public protocol TextFieldStyle {}

@MainActor public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}
}

@MainActor public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}
}

@MainActor public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}
}

@MainActor public struct SquareBorderTextFieldStyle: TextFieldStyle {
    public init() {}
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() }
}

extension TextFieldStyle where Self == SquareBorderTextFieldStyle {
    public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() }
}

enum TextFieldStyleKind: Equatable {
    case automatic
    case plain
    case roundedBorder
    case squareBorder
}

@MainActor
protocol _TextFieldStyleResolvable {
    var textFieldStyleKind: TextFieldStyleKind { get }
}

extension DefaultTextFieldStyle: _TextFieldStyleResolvable {
    var textFieldStyleKind: TextFieldStyleKind { .automatic }
}

extension PlainTextFieldStyle: _TextFieldStyleResolvable {
    var textFieldStyleKind: TextFieldStyleKind { .plain }
}

extension RoundedBorderTextFieldStyle: _TextFieldStyleResolvable {
    var textFieldStyleKind: TextFieldStyleKind { .roundedBorder }
}

extension SquareBorderTextFieldStyle: _TextFieldStyleResolvable {
    var textFieldStyleKind: TextFieldStyleKind { .squareBorder }
}

private struct TextFieldStyleKindEnvironmentKey: EnvironmentKey {
    static var defaultValue: TextFieldStyleKind { .automatic }
}

extension EnvironmentValues {
    var textFieldStyleKind: TextFieldStyleKind {
        get { self[TextFieldStyleKindEnvironmentKey.self] }
        set { self[TextFieldStyleKindEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
        let kind = (style as? any _TextFieldStyleResolvable)?.textFieldStyleKind ?? .automatic
        return environment(\.textFieldStyleKind, kind)
    }
}
