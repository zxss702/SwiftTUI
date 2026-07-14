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

    /// `navigationDestination(item:)` 注册的 binding 桥：pop / path 变更时由 Context 清空 item，不依赖源页仍挂在树上。
    @ObservationIgnored
    private var itemBridges: [UUID: NavigationItemBridge] = [:]

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
        notifyChromeChange()
        syncToBinding()
        notifyItemBridges()
    }

    var canPop: Bool { !stack.isEmpty }

    // MARK: - Item binding bridges

    func registerItemBridge(_ bridge: NavigationItemBridge) {
        itemBridges[bridge.id] = bridge
    }

    func unregisterItemBridge(id: UUID) {
        itemBridges.removeValue(forKey: id)
    }

    private func notifyItemBridges() {
        for bridge in itemBridges.values {
            bridge.stackDidChange(stack)
        }
    }

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
        notifyChromeChange()
    }

    /// 由页面 `.toolbar` 在每次 body 求值时上报到当前页 id
    func setToolbarForCurrentPage(_ content: NavigationToolbarContent) {
        setToolbar(content, for: currentPageID)
    }

    func setToolbar(_ content: NavigationToolbarContent, for id: AnyHashable) {
        // Always replace slot views (AnyView identity); bump only for the top page
        // so keep-alive pages re-registering cannot storm the bar.
        toolbars[id] = content
        guard id == currentPageID else { return }
        toolbarEpoch &+= 1
    }

    func toolbar(for id: AnyHashable) -> NavigationToolbarContent {
        toolbars[id] ?? .empty
    }

    var currentToolbar: NavigationToolbarContent {
        toolbar(for: currentPageID)
    }

    private func notifyChromeChange() {
        toolbarEpoch &+= 1
    }

    func destinationView(for value: AnyHashable) -> AnyView? {
        if let direct = directDestinations[value] {
            return direct
        }
        let key = ObjectIdentifier(type(of: value.base))
        guard let builder = destinations[key] else { return nil }
        // 按 path 值缓存，避免 NavigationPage 每次 body 重建页面把 @State 初始值冲掉。
        let view = builder(value)
        directDestinations[value] = view
        return view
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
        notifyItemBridges()
    }

    private func syncToBinding() {
        pathSync?.write(stack)
    }
}

// MARK: - navigationDestination(item:) bridge

/// 由 Context 在栈变化时回调，清空已不在栈上的 item Binding（对齐 SwiftUI：导航系统拥有 path↔item 同步）。
@MainActor
final class NavigationItemBridge {
    let id: UUID
    /// 当前由该 bridge push 上去的值；与源页生命周期解耦。
    var presented: AnyHashable?
    var clearItemHandler: () -> Void

    init(id: UUID = UUID(), clearItem: @escaping () -> Void = {}) {
        self.id = id
        self.clearItemHandler = clearItem
    }

    func stackDidChange(_ stack: [AnyHashable]) {
        guard let presented else { return }
        if !stack.contains(presented) {
            self.presented = nil
            clearItemHandler()
        }
    }
}

// MARK: - Environment lookup

@MainActor
enum NavigationEnvironment {
    /// 从 node 解析环境（使用缓存）。
    static func values(from node: Node) -> EnvironmentValues {
        node.resolvedEnvironment()
    }
}
