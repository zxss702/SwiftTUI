import Foundation

// MARK: - NavigationLink

/// TUI 版 NavigationLink，公开形状与 SwiftUI 对齐。
@MainActor public struct NavigationLink<Label: View, Destination: View>: View {
    let label: Label
    let performNavigation: @MainActor (NavigationContext) -> Void

    private init(
        label: Label,
        performNavigation: @escaping @MainActor (NavigationContext) -> Void
    ) {
        self.label = label
        self.performNavigation = performNavigation
    }

    public var body: some View {
        NavigationLinkBody(label: label, performNavigation: performNavigation)
    }
}

// MARK: - Value-based（Destination == Never）

extension NavigationLink where Destination == Never {
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {
        self.init(label: label()) { context in
            guard let value else { return }
            context.push(value)
        }
    }

    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) where Label == Text {
        self.init(value: value, label: { Text(String(title)) })
    }
}

// MARK: - Destination-based

extension NavigationLink {
    public init(
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        // 与 SwiftUI 一致：点击时再构建 destination，避免列表刷新时过早求值 / 绑到错误数据。
        self.init(label: label()) { context in
            context.pushDirect(
                id: NavigationDirectDestinationID(),
                destination: AnyView(destination())
            )
        }
    }
}

extension NavigationLink where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination: destination, label: { Text(String(title)) })
    }
}

// MARK: - Body

@MainActor
private struct NavigationLinkBody<Label: View>: View {
    let label: Label
    let performNavigation: @MainActor (NavigationContext) -> Void

    @Environment(NavigationContext.self) private var context

    var body: some View {
        let navigation = context
        Button {
            performNavigation(navigation)
        } label: {
            label
        }
    }
}

// MARK: - Direct destination token

@MainActor
final class NavigationDirectDestinationID: Hashable {
    nonisolated static func == (lhs: NavigationDirectDestinationID, rhs: NavigationDirectDestinationID) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated let id: UUID = UUID()
}
