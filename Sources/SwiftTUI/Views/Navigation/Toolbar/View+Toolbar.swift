import Foundation

// MARK: - toolbar

public extension View {
    /// 为当前导航页注册工具栏内容；与返回按钮、title 同一行显示。
    func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        ToolbarModifierView(toolbar: content(), content: self)
    }
}

// MARK: - Modifier

/// 用 PrimitiveView 在 node 上解析 `NavigationContext`，避免页面卸载 / 返回时
/// `@Environment` 在已脱离层级的节点上 fatalError。
@MainActor
private struct ToolbarModifierView<Content: View, Toolbar: ToolbarContent>: View, PrimitiveView {
    let toolbar: Toolbar
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        registerToolbar(on: node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        registerToolbar(on: node)
        node.children[0].update(using: content.view)
    }

    private func registerToolbar(on node: Node) {
        let env = NavigationEnvironment.values(from: node)
        guard let context = env[NavigationContext.self] else { return }

        // 绑定到首次注册时的 pageID；返回后若本节点仍被 Observation 刷新，不再写入新当前页
        let pageID: AnyHashable
        if let stored = node.state["toolbarPageID"] as? AnyHashable {
            pageID = stored
        } else {
            pageID = context.currentPageID
            node.state["toolbarPageID"] = pageID
        }
        guard pageID == context.currentPageID else { return }

        var storage = NavigationToolbarContent.empty
        (toolbar as? any _ToolbarContentCollectable)?.collect(into: &storage)
        context.setToolbar(storage, for: pageID)
    }
}
