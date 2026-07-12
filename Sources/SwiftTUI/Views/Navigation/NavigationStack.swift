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
            // 工具栏单独成 View，title 变化只刷新栏，避免整页重建闪烁
            NavigationBar(context: context, navigateBack: navigateBack)

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

@MainActor
private struct NavigationBar: View {
    let context: NavigationContext
    let navigateBack: () -> Void

    var body: some View {
        let toolbar = context.currentToolbar

        HStack(spacing: 1) {
            if context.canPop {
                Button(context.backButtonLabel, action: navigateBack)
            }
            if let leading = toolbar.leading {
                leading
            }

            middle(toolbar: toolbar)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing = toolbar.trailing {
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 1)
    }

    @ViewBuilder
    private func middle(toolbar: NavigationToolbarContent) -> some View {
        if let principal = toolbar.principal {
            principal
        } else {
            Text(context.currentTitle)
                .bold()
                .lineLimit(1)
        }
    }
}

// MARK: - Page

/// 只挂载当前可见页（根或栈顶），与 SwiftUI NavigationStack 的展示模型一致：
/// path 驱动内容；源页不必为了 item 同步而常驻隐藏树。
@MainActor
private struct NavigationPage<Root: View>: View {
    let root: Root
    let context: NavigationContext

    var body: some View {
        if context.canPop,
           let topValue = context.stack.last,
           let destination = context.destinationView(for: topValue)
        {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            root
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
