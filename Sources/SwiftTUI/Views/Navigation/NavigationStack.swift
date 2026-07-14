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

/// Observes `NavigationContext.toolbarEpoch` / titles so chrome updates without
/// invalidating the whole stack (which would re-run page body → setToolbar → loop).
@MainActor
private struct NavigationBar: View {
    let navigateBack: () -> Void
    let context: NavigationContext

    var body: some View {
        // Read observable fields so chrome refreshes without `@Environment`
        // (avoids escaping-closure / weak-node traps).
        let _ = context.toolbarEpoch
        let _ = context.stack
        let toolbar = context.toolbar(for: context.currentPageID)
        let title = context.currentTitle
        let canPop = context.canPop
        let backLabel = context.backButtonLabel

        HStack(spacing: 1) {
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

        ZStack {
            root
                .hidden(!stack.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ForEach(stack, id: \.self) { value in
                pageView(for: value)
                    .hidden(stack.last.map { $0 != value } ?? true)
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
