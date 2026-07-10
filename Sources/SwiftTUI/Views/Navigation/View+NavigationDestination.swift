import Foundation

// MARK: - navigationDestination

public extension View {
    /// 注册一种值类型对应的目标 View，配合 `NavigationLink(value:)` 使用。
    func navigationDestination<D: Hashable, V: View>(
        for type: D.Type,
        @ViewBuilder destination: @escaping (D) -> V
    ) -> some View {
        NavigationDestinationView(
            type: type,
            destination: destination,
            content: self
        )
    }
}

// MARK: - NavigationDestinationView

@MainActor
private struct NavigationDestinationView<Content: View, D: Hashable, Destination: View>: View {
    let type: D.Type
    let destination: (D) -> Destination
    let content: Content

    @Environment(NavigationContext.self) private var context

    var body: some View {
        // 每次 body 求值时注册（destinations 为 ObservationIgnored，不会触发闪烁）
        let _ = context.registerDestination(for: type) { value in
            AnyView(destination(value))
        }
        content
    }
}
