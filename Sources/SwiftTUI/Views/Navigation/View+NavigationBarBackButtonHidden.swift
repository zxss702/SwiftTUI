import Foundation

public extension View {
    /// 设置当前导航页是否隐藏导航栏返回按钮，不影响程序化返回。
    func navigationBarBackButtonHidden(_ hidden: Bool = true) -> some View {
        NavigationBackButtonHiddenView(hidden: hidden, content: self)
    }
}

@MainActor
private struct NavigationBackButtonHiddenView<Content: View>: View, PrimitiveView {
    let hidden: Bool
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        register(on: node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        register(on: node)
    }

    private func register(on node: Node) {
        guard let context = node.resolvedEnvironment()[NavigationContext.self] else { return }
        let boundPageKey = "navigation.boundPageID"
        if node.storage[boundPageKey] == nil {
            node.storage[boundPageKey] = context.currentPageID
        }
        guard let bound = node.storage[boundPageKey] as? AnyHashable else { return }
        context.setBackButtonHidden(hidden, for: bound)
    }
}
