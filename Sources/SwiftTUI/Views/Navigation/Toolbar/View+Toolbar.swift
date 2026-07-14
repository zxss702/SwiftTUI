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
        node.children[0].update(using: content.view)
        registerToolbar(on: node)
    }

    private func registerToolbar(on node: Node) {
        guard let context = node.resolvedEnvironment()[NavigationContext.self] else { return }
        let boundPageKey = "navigation.boundPageID"
        // Bind once to the page that first mounted this modifier — never reuse `@State` slots.
        if node.storage[boundPageKey] == nil {
            node.storage[boundPageKey] = context.currentPageID
        }
        guard let bound = node.storage[boundPageKey] as? AnyHashable else { return }
        // Keep-alive pages stay mounted; only the top page may publish chrome.
        guard bound == context.currentPageID else { return }

        var storage = NavigationToolbarContent.empty
        (toolbar as? any _ToolbarContentCollectable)?.collect(into: &storage)
        context.setToolbar(storage, for: bound)
    }
}
