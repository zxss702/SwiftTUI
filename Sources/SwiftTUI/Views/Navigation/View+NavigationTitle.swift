import Foundation

// MARK: - navigationTitle

public extension View {
    /// 设置当前导航页标题。在 `onAppear` 时写入 `NavigationContext.titles[pageID]`。
    func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        NavigationTitleView(title: String(title), content: self)
    }
}

// MARK: - NavigationTitleView

@MainActor
private struct NavigationTitleView<Content: View>: View {
    let title: String
    let content: Content

    @Environment(NavigationContext.self) private var context

    var body: some View {
        content.onAppear {
            context.setTitleForCurrentPage(title)
        }
    }
}
