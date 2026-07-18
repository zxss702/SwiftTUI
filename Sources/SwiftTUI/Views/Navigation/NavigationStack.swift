import Foundation

// MARK: - NavigationStack

/// TUI 版 NavigationStack。每个实例独立持有 `NavigationContext`，互不合并。
@MainActor public struct NavigationStack<Data, Root: View>: View {
    let root: Root
    let pathSync: NavigationPathSync?

    @State private var context = NavigationContext()

    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root()
        self.pathSync = nil
    }

    public init(
        path: Binding<NavigationPath>,
        @ViewBuilder root: () -> Root
    ) where Data == NavigationPath {
        self.root = root()
        self.pathSync = .navigationPath(path)
    }

    public init(
        path: Binding<Data>,
        @ViewBuilder root: () -> Root
    ) where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
            Data.Element: Hashable
    {
        self.root = root()
        self.pathSync = .typed(path)
    }

    public var body: some View {
        NavigationContainer(root: root, pathSync: pathSync, context: context)
            .environment(context)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Container（注入 dismiss，同步 path）

@MainActor
private struct NavigationContainer<Root: View>: View {
    let root: Root
    let pathSync: NavigationPathSync?
    let context: NavigationContext

    @Environment(\.dismiss) private var parentDismiss

    var body: some View {
        let _ = context.installPathSync(pathSync)

        VStack(alignment: .leading, spacing: 0) {
            NavigationBar(navigateBack: navigateBack, context: context)

            NavigationPage(root: root, context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.dismiss, DismissAction(action: navigateBack))
    }

    private func navigateBack() {
        if context.canPop {
            context.pop()
        } else {
            parentDismiss()
        }
    }
}

// MARK: - Bar

/// 导航栏：`stack` / `titles` 走 Observation；toolbar 槽位由
/// `NavigationContext.notifyChromeChange()` **只 invalidate 本节点**刷新，
/// 这样页面 `.toolbar` 里用 `@State` 与 SwiftUI 一样能更新，又不会和
/// `setToolbar` 互相 Observation 死循环。
@MainActor
private struct NavigationBar: View, PrimitiveView {
    let navigateBack: () -> Void
    let context: NavigationContext

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        context.chromeBarNode = node
        let content = node.observing {
            // Track stack/titles for back label & plain title; toolbar slots are
            // ObservationIgnored and refreshed via chromeBarNode invalidate.
            let _ = context.stack
            let _ = context.titles
            return barContent().view
        }
        node.addNode(at: 0, Node(view: content))
    }

    func updateNode(_ node: Node) {
        context.chromeBarNode = node
        let content = node.observing {
            let _ = context.stack
            let _ = context.titles
            return barContent().view
        }
        node.children[0].update(using: content)
    }

    private func barContent() -> some View {
        let toolbar = context.toolbar(for: context.currentPageID)
        let title = context.currentTitle
        let canPop = context.canPop
        let backLabel = context.backButtonLabel

        return HStack(spacing: 1) {
            if canPop {
                Button(backLabel, action: navigateBack)
            }
            if let leading = toolbar.leading {
                leading
            }

            middle(toolbar: toolbar, title: title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing = toolbar.trailing {
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 1)
    }

    @ViewBuilder
    private func middle(toolbar: NavigationToolbarContent, title: String) -> some View {
        if let principal = toolbar.principal {
            principal
        } else if let titleMenu = toolbar.titleMenu {
            Menu {
                titleMenu
            } label: {
                Text(title)
                    .bold()
                    .lineLimit(1)
            }
        } else {
            Text(title)
                .bold()
                .lineLimit(1)
        }
    }
}

// MARK: - Page (keep-alive stack)

/// Keeps root + every pushed page mounted. Only the top page is visible and
/// hit-testable; lower pages stay in the view graph so `@State` survives push/pop.
@MainActor
private struct NavigationPage<Root: View>: View {
    let root: Root
    let context: NavigationContext

    var body: some View {
        let stack = context.stack
        // Encode top-ness into ForEach elements so survivor equality sees
        // `.hidden` flips when the path value itself is unchanged.
        let pages = stack.map { KeepAlivePage(value: $0, isTop: $0 == stack.last) }

        ZStack {
            root
                .hidden(!stack.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(pages, id: \.value) { page in
                pageView(for: page.value)
                    .hidden(!page.isTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func pageView(for value: AnyHashable) -> some View {
        if let destination = context.destinationView(for: value) {
            destination
        } else {
            EmptyView()
        }
    }
}

/// ForEach row for keep-alive pages. `isTop` is part of equality so a push that
/// covers an existing page still updates that survivor's `.hidden` modifier.
private struct KeepAlivePage: Hashable {
    let value: AnyHashable
    let isTop: Bool
}
