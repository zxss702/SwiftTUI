import Foundation
import Observation

/// The node of a view graph.
///
/// The view graph is the runtime representation of the views in an application.
/// Every view corresponds to a node. If a view is used in multiple places, in
/// each of the places it is used it will have a seperate node.
///
/// Once (a part of) the node tree is built, views can update the node tree, as
/// long as their type match. This is done by the views themselves.
///
/// Note that the control tree more closely resembles the layout hierarchy,
/// because structural views (ForEach, etc.) have their own node.
@MainActor
final class Node {
    var view: GenericView

    /// Slot-indexed `@State` / `@FocusState` / `@Query` storage.
    var state: [Int: Any] = [:]
    /// Framework ephemeral keys (onChange, presentation, scroll proxy, query observers).
    var storage: [String: Any] = [:]
    var environment: ((inout EnvironmentValues) -> Void)? {
        didSet { invalidateEnvironmentCache() }
    }
    /// Cached environment values for this node (invalidated when ancestor env changes).
    var cachedEnvironment: EnvironmentValues?
    var environmentCacheValid = false

    var element: Element?
    weak var application: Application?

    /// Set by `hidden(true)` keep-alive pages (NavigationStack). Observation may
    /// still dirty these nodes, but the host skips `update` until visible again.
    var suppressUpdates = false

    /// True when this node or any ancestor is suppressed (new nodes under a
    /// hidden page may not have the flag copied yet).
    var isUpdateSuppressed: Bool {
        var current: Node? = self
        while let node = current {
            if node.suppressUpdates { return true }
            current = node.parent
        }
        return false
    }

    /// Propagate update suppression to the whole subtree (navigation keep-alive).
    func setSubtreeUpdateSuppressed(_ suppressed: Bool) {
        suppressUpdates = suppressed
        for child in children {
            child.setSubtreeUpdateSuppressed(suppressed)
        }
    }

    func invalidateEnvironmentCache() {
        environmentCacheValid = false
        cachedEnvironment = nil
        for child in children {
            child.invalidateEnvironmentCache()
        }
    }

    /// Resolve and cache `EnvironmentValues` for this node.
    func resolvedEnvironment() -> EnvironmentValues {
        if environmentCacheValid, let cachedEnvironment {
            return cachedEnvironment
        }
        var transforms: [(inout EnvironmentValues) -> Void] = []
        var current: Node? = self
        while let c = current {
            if let t = c.environment {
                transforms.insert(t, at: 0)
            }
            current = c.parent
        }
        var env = EnvironmentValues()
        for t in transforms {
            t(&env)
        }
        cachedEnvironment = env
        environmentCacheValid = true
        return env
    }

    /// For modifiers only, references to the controls
    var elements: WeakSet<Element>?

    private(set) weak var parent: Node?
    private(set) var children: [Node] = []

    private(set) var index: Int = 0

    private(set) var built = false

    init(view: GenericView) {
        self.view = view
    }

    func update(using view: GenericView) {
        build()
        withObservationTracking {
            view.updateNode(self)
        } onChange: { [weak self] in
            // PopupPresenter.stack 等 @Observable 在 MainActor 上变更时同步弄脏节点，
            // 让 Application.update 的 drain 能在同一帧卸掉 sheet/popover，避免 dismiss 卡住。
            Self.scheduleInvalidate(self)
        }
    }

    var root: Node { parent?.root ?? self }

    /// 是否仍挂在指定 `Application` 的视图树上。
    /// `removeNode` 后 parent 为 nil；孤立子树的 `root` 是自身且 `application == nil`。
    func isAttached(to application: Application) -> Bool {
        root.application === application
    }

    /// The total number of controls in the node.
    /// The node does not need to be fully built for the size to be computed.
    var size: Int {
        if let size = type(of: view).size { return size }
        build()
        return children.map(\.size).reduce(0, +)
    }

    /// The number of controls in the parent node _before_ the current node.
    private var offset: Int {
        var offset = 0
        for i in 0 ..< index {
            offset += parent?.children[i].size ?? 0
        }
        return offset
    }

    func build() {
        if !built {
            withObservationTracking {
                self.view.buildNode(self)
            } onChange: { [weak self] in
                Self.scheduleInvalidate(self)
            }
            built = true
            if !(view is OptionalView), let container = view as? LayoutRootView {
                container.loadData(node: self)
            }
        }
    }

    /// Observation `onChange` is nonisolated. When already on the main thread
    /// (typical during host commit), invalidate synchronously into the open
    /// Transaction; otherwise hop with `Task`.
    private nonisolated static func scheduleInvalidate(_ node: Node?) {
        guard let node else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                node.root.application?.invalidateNode(node)
            }
        } else {
            Task { @MainActor in
                node.root.application?.invalidateNode(node)
            }
        }
    }

    // MARK: - Changing nodes

    func addNode(at index: Int, _ node: Node) {
        guard node.parent == nil else { fatalError("Node is already in tree") }
        children.insert(node, at: index)
        node.parent = self
        for i in index ..< children.count {
            children[i].index = i
        }
        if built {
            for i in 0 ..< node.size {
                insertElement(at: node.offset + i)
            }
            root.application?.requestLayout()
        }
    }

    func removeNode(at index: Int) {
        if built {
            for i in (0 ..< children[index].size).reversed() {
                removeElement(at: children[index].offset + i)
            }
            root.application?.requestLayout()
        }
        children[index].parent = nil
        children.remove(at: index)
        for i in index ..< children.count {
            children[i].index = i
        }
    }

    // MARK: - Container data source

    func element(at offset: Int) -> Element {
        build()
        if offset == 0, let element = self.element { return element }
        var i = 0
        for child in children {
            let size = child.size
            if (offset - i) < size {
                let element = child.element(at: offset - i)
                if !(view is OptionalView), let modifier = self.view as? ModifierView {
                    return modifier.passElement(element, node: self)
                }
                return element
            }
            i += size
        }
        fatalError("Out of bounds")
    }

    // MARK: - Container changes

    private func insertElement(at offset: Int) {
        if !(view is OptionalView), let container = view as? LayoutRootView {
            container.insertElement(at: offset, node: self)
            return
        }
        parent?.insertElement(at: offset + self.offset)
    }

    private func removeElement(at offset: Int) {
        if !(view is OptionalView), let container = view as? LayoutRootView {
            container.removeElement(at: offset, node: self)
            return
        }
        parent?.removeElement(at: offset + self.offset)
    }
}
