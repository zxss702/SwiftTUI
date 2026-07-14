import Foundation

// MARK: - navigationTitle

public extension View {
    /// 设置当前导航页标题。绑定到首次挂载时的 page id，keep-alive 下页不会覆盖顶页标题。
    func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        NavigationTitleView(title: String(title), content: self)
    }
}

// MARK: - NavigationTitleView

@MainActor
private struct NavigationTitleView<Content: View>: View, PrimitiveView {
    let title: String
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        registerTitle(on: node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        registerTitle(on: node)
    }

    private func registerTitle(on node: Node) {
        guard let context = node.resolvedEnvironment()[NavigationContext.self] else { return }
        let boundPageKey = "navigation.boundPageID"
        if node.storage[boundPageKey] == nil {
            node.storage[boundPageKey] = context.currentPageID
        }
        guard let bound = node.storage[boundPageKey] as? AnyHashable else { return }
        context.setTitle(title, for: bound)
    }
}
