import Foundation
import Observation

// MARK: - Path Sync

/// 将内部 `[AnyHashable]` 栈与外部 `NavigationPath` 或 typed path binding 同步。
@MainActor
struct NavigationPathSync {
    let read: () -> [AnyHashable]
    let write: ([AnyHashable]) -> Void

    static func navigationPath(_ binding: Binding<NavigationPath>) -> NavigationPathSync {
        NavigationPathSync(
            read: { binding.wrappedValue.elements },
            write: { elements in
                var path = binding.wrappedValue
                path.elements = elements
                binding.wrappedValue = path
            }
        )
    }

    static func typed<Data>(
        _ binding: Binding<Data>
    ) -> NavigationPathSync
    where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection,
          Data.Element: Hashable
    {
        NavigationPathSync(
            read: { binding.wrappedValue.map { AnyHashable($0) } },
            write: { elements in
                var data = Data()
                for element in elements {
                    if let value = element.base as? Data.Element {
                        data.append(value)
                    }
                }
                binding.wrappedValue = data
            }
        )
    }
}

// MARK: - Root page id

/// 根页在 `titles` 字典中的稳定 key（栈为空时的当前页）。
struct NavigationRootID: Hashable {
    static let shared = NavigationRootID()
}

// MARK: - NavigationContext

/// 单个 NavigationStack 的导航控制器；每个 Stack 独立持有。
@Observable
@MainActor final class NavigationContext {

    var stack: [AnyHashable] = []

    @ObservationIgnored
    var destinations: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    @ObservationIgnored
    var directDestinations: [AnyHashable: AnyView] = [:]

    /// 页面标题：key 为页面 id（根页用 `NavigationRootID`，其余为栈上的值）
    var titles: [AnyHashable: String] = [:]

    /// 各页工具栏三槽；写入时 bump `toolbarEpoch` 以刷新 NavigationBar。
    @ObservationIgnored
    var toolbars: [AnyHashable: NavigationToolbarContent] = [:]

    /// NavigationBar 观察此值以在 toolbar 内容变化时刷新。
    var toolbarEpoch: Int = 0

    /// Coalesce async toolbarEpoch bumps scheduled in the same turn.
    @ObservationIgnored
    private var toolbarBumpScheduled = false

    /// 当前页 id
    var currentPageID: AnyHashable {
        stack.last ?? AnyHashable(NavigationRootID.shared)
    }

    /// 上级页 id（可 pop 时才有）
    var parentPageID: AnyHashable? {
        guard !stack.isEmpty else { return nil }
        if stack.count == 1 {
            return AnyHashable(NavigationRootID.shared)
        }
        return stack[stack.count - 2]
    }

    var currentTitle: String {
        titles[currentPageID] ?? ""
    }

    /// 上级标题；无标题时为空，导航栏应显示 `⟨返回`
    var backTitle: String {
        guard let parentPageID else { return "" }
        return titles[parentPageID] ?? ""
    }

    /// 返回按钮文案：有上级 title 用 `⟨Title`，否则 `⟨返回`
    var backButtonLabel: String {
        let parent = backTitle
        return parent.isEmpty ? "⟨返回" : "⟨\(parent)"
    }

    @ObservationIgnored
    var pathSync: NavigationPathSync?

    public init() {}

    // MARK: - 栈操作

    public func push<V: Hashable>(_ value: V) {
        stack.append(AnyHashable(value))
        syncToBinding()
    }

    func pushDirect(id: some Hashable, destination: AnyView) {
        let key = AnyHashable(id)
        directDestinations[key] = destination
        stack.append(key)
        syncToBinding()
    }

    public func pop() {
        guard !stack.isEmpty else { return }
        let removed = stack.removeLast()
        directDestinations.removeValue(forKey: removed)
        titles.removeValue(forKey: removed)
        toolbars.removeValue(forKey: removed)
        toolbarEpoch &+= 1
        syncToBinding()
    }

    var canPop: Bool { !stack.isEmpty }

    // MARK: - Destinations / Title

    func registerDestination<D: Hashable>(for type: D.Type, builder: @escaping (D) -> AnyView) {
        let key = ObjectIdentifier(D.self)
        destinations[key] = { anyHashable in
            if let value = anyHashable.base as? D {
                return builder(value)
            }
            return AnyView(EmptyView())
        }
    }

    /// 由页面 `.navigationTitle` 在 onAppear 时上报到当前页 id
    func setTitleForCurrentPage(_ title: String) {
        setTitle(title, for: currentPageID)
    }

    func setTitle(_ title: String, for id: AnyHashable) {
        guard titles[id] != title else { return }
        titles[id] = title
    }

    /// 由页面 `.toolbar` 在每次 body 求值时上报到当前页 id
    func setToolbarForCurrentPage(_ content: NavigationToolbarContent) {
        setToolbar(content, for: currentPageID)
    }

    func setToolbar(_ content: NavigationToolbarContent, for id: AnyHashable) {
        toolbars[id] = content
        // 异步 bump，避免在页面 body 的 Observation 追踪里读写 epoch 造成循环刷新。
        // 同一轮内多次 registerToolbar 只 bump 一次。
        guard !toolbarBumpScheduled else { return }
        toolbarBumpScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.toolbarBumpScheduled = false
            self.toolbarEpoch &+= 1
        }
    }

    func toolbar(for id: AnyHashable) -> NavigationToolbarContent {
        toolbars[id] ?? .empty
    }

    var currentToolbar: NavigationToolbarContent {
        _ = toolbarEpoch
        return toolbar(for: currentPageID)
    }

    func destinationView(for value: AnyHashable) -> AnyView? {
        if let direct = directDestinations[value] {
            return direct
        }
        let key = ObjectIdentifier(type(of: value.base))
        return destinations[key]?(value)
    }

    // MARK: - Path sync

    func installPathSync(_ sync: NavigationPathSync?) {
        pathSync = sync
        syncFromBinding()
    }

    func syncFromBinding() {
        guard let pathSync else { return }
        let newStack = pathSync.read()
        guard newStack != stack else { return }
        stack = newStack
    }

    private func syncToBinding() {
        pathSync?.write(stack)
    }
}

// MARK: - Environment lookup

@MainActor
enum NavigationEnvironment {
    /// 从 node 父链解析环境（子节点 environment 覆盖父节点）。
    static func values(from node: Node) -> EnvironmentValues {
        func build(node: Node, transform: (inout EnvironmentValues) -> Void) -> EnvironmentValues {
            if let parent = node.parent {
                return build(node: parent) {
                    node.environment?(&$0)
                    transform(&$0)
                }
            }
            var env = EnvironmentValues()
            node.environment?(&env)
            transform(&env)
            return env
        }
        return build(node: node, transform: { _ in })
    }
}
