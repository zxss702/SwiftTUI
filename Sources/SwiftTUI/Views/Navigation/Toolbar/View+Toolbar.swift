import Foundation

// MARK: - toolbar

public extension View {
    /// 为当前导航页注册工具栏内容；与返回按钮、title 同一行显示。
    func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> some View {
        ToolbarModifierView(toolbar: content(), content: self)
    }

    /// 将 `navigationTitle` 变成可下拉菜单，并定义菜单项。
    func toolbarTitleMenu<MenuContent: View>(
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        ToolbarTitleMenuModifierView(menu: content(), content: self)
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

        // Collect under `observing`: custom `ToolbarContent.body` often reads
        // `@Observable` / `@Bindable` (e.g. `if let record = observer.record`).
        // Without this, chrome stays empty until a GeometryReader resize rebuilds
        // the page and re-registers the toolbar.
        var storage = NavigationToolbarContent.empty
        node.observing {
            collectToolbarContent(toolbar, into: &storage)
        }
        context.setToolbar(storage, for: bound)
    }
}

// MARK: - toolbarTitleMenu

@MainActor
private struct ToolbarTitleMenuModifierView<Content: View, MenuContent: View>: View, PrimitiveView {
    let menu: MenuContent
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        registerTitleMenu(on: node)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        registerTitleMenu(on: node)
    }

    private func registerTitleMenu(on node: Node) {
        guard let context = node.resolvedEnvironment()[NavigationContext.self] else { return }
        let boundPageKey = "navigation.boundPageID"
        if node.storage[boundPageKey] == nil {
            node.storage[boundPageKey] = context.currentPageID
        }
        guard let bound = node.storage[boundPageKey] as? AnyHashable else { return }
        guard bound == context.currentPageID else { return }
        let menuView = node.observing { AnyView(menu) }
        context.setTitleMenu(menuView, for: bound)
    }
}
