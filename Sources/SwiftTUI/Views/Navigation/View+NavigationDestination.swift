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
    /// `item` 非 `nil` 时 push；变为 `nil` 或用户返回时 pop 并清空 Binding。
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

@MainActor
private struct NavigationDestinationItemView<Content: View, D: Hashable, Destination: View>: View {
    @Binding var item: D?
    let destination: (D) -> Destination
    let content: Content

    @Environment(NavigationContext.self) private var context
    @State private var presented: D?

    var body: some View {
        let _ = context.registerDestination(for: D.self) { value in
            AnyView(destination(value))
        }

        content
            .onChange(of: item, initial: true) { _, newValue in
                syncItemToStack(newValue)
            }
            .onChange(of: context.stack) { _, _ in
                syncStackToItem()
            }
    }

    private func syncItemToStack(_ newValue: D?) {
        if let newValue {
            if presented == newValue,
               let last = context.stack.last?.base as? D,
               last == newValue {
                return
            }
            if let presented,
               let last = context.stack.last?.base as? D,
               last == presented {
                context.pop()
            }
            context.push(newValue)
            presented = newValue
        } else if let presented {
            if let last = context.stack.last?.base as? D, last == presented {
                context.pop()
            }
            self.presented = nil
        }
    }

    private func syncStackToItem() {
        guard let presented else { return }
        let stillPresent = context.stack.contains { ($0.base as? D) == presented }
        if !stillPresent {
            self.presented = nil
            if item != nil {
                item = nil
            }
        }
    }
}
