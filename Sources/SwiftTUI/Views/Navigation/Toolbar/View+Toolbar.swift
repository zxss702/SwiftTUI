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
private struct ToolbarModifierView<Content: View, Toolbar: ToolbarContent>: View {
    let toolbar: Toolbar
    let content: Content

    @Environment(NavigationContext.self) private var context
    @State private var boundPageID: AnyHashable?

    var body: some View {
        let _ = registerToolbar()
        content
            .onAppear {
                if boundPageID == nil {
                    boundPageID = context.currentPageID
                }
            }
    }

    private func registerToolbar() {
        let pageID = boundPageID ?? context.currentPageID
        guard pageID == context.currentPageID else { return }

        var storage = NavigationToolbarContent.empty
        (toolbar as? any _ToolbarContentCollectable)?.collect(into: &storage)
        context.setToolbar(storage, for: pageID)
    }
}
