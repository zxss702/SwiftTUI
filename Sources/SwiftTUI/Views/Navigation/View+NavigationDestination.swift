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

    /// 用可选 Binding 驱动入栈/出栈，对齐 SwiftUI `navigationDestination(item:destination:)`。
    /// `item` 非 `nil` 时 push；变为 `nil` 或用户返回时由 `NavigationContext` 清空 Binding。
    func navigationDestination<D: Hashable, C: View>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        NavigationDestinationItemView(
            item: item,
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

// MARK: - NavigationDestinationItemView

/// - item → push：源页仍在树上时由本视图完成
/// - pop → 清 item：由 `NavigationContext` 持有的 bridge 完成（不依赖源页仍挂树 / 不观察 stack）
@MainActor
private struct NavigationDestinationItemView<Content: View, D: Hashable, Destination: View>: View {
    @Binding var item: D?
    let destination: (D) -> Destination
    let content: Content

    @Environment(NavigationContext.self) private var context
    @State private var bridge = NavigationItemBridge(clearItem: {})

    var body: some View {
        let navigation = context
        let _ = navigation.registerDestination(for: D.self) { value in
            AnyView(destination(value))
        }
        let _ = configureBridge(on: navigation)

        content
            .onChange(of: item, initial: true) { _, newValue in
                syncItemToStack(newValue, navigation: navigation)
            }
            .onDisappear {
                navigation.unregisterItemBridge(id: bridge.id)
            }
    }

    private func configureBridge(on navigation: NavigationContext) {
        let binding = $item
        bridge.clearItemHandler = {
            if binding.wrappedValue != nil {
                binding.wrappedValue = nil
            }
        }
        navigation.registerItemBridge(bridge)
    }

    private func syncItemToStack(_ newValue: D?, navigation: NavigationContext) {
        if let newValue {
            if bridge.presented == AnyHashable(newValue),
               let last = navigation.stack.last?.base as? D,
               last == newValue {
                return
            }
            if let current = bridge.presented?.base as? D,
               let last = navigation.stack.last?.base as? D,
               last == current {
                navigation.pop()
            }
            navigation.push(newValue)
            bridge.presented = AnyHashable(newValue)
        } else if let current = bridge.presented?.base as? D {
            if let last = navigation.stack.last?.base as? D, last == current {
                navigation.pop()
            }
            bridge.presented = nil
        }
    }
}