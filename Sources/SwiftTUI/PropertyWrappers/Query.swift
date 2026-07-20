import Foundation
#if canImport(SwiftData)
import SwiftData
#else
import JsonData
import GRDB

public typealias Predicate<T: PersistentModel> = JsonDataCore.Predicate<T>
public typealias SortDescriptor<T: PersistentModel> = JsonDataCore.SortDescriptor<T>
public typealias FetchDescriptor<T: PersistentModel> = JsonDataCore.FetchDescriptor<T>
#endif

#if canImport(SwiftData)
/// Nonisolated — NotificationCenter callbacks are not MainActor.
private func swiftDataPersistentIdentifiers(
    in userInfo: [AnyHashable: Any]?,
    key: ModelContext.NotificationKey
) -> Set<PersistentIdentifier> {
    guard let userInfo, let value = userInfo[key] else { return [] }
    if let set = value as? Set<PersistentIdentifier> {
        return set
    }
    if let array = value as? [PersistentIdentifier] {
        return Set(array)
    }
    if let dict = value as? [String: Set<PersistentIdentifier>] {
        return dict.values.reduce(into: Set()) { $0.formUnion($1) }
    }
    if let dict = value as? [String: [PersistentIdentifier]] {
        return dict.values.reduce(into: Set()) { $0.formUnion($1) }
    }
    return []
}
#endif

// A wrapper to ensure NotificationCenter observers are removed when the node is destroyed
private final class NotificationTokenBox {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) {
        self.token = token
    }
    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

#if !canImport(SwiftData)
/// Keeps JsonData membership observation + contextDidChange token alive on the node.
private final class JsonDataQueryObservationBox {
    let cancellable: AnyDatabaseCancellable
    let noteToken: NSObjectProtocol

    init(cancellable: AnyDatabaseCancellable, noteToken: NSObjectProtocol) {
        self.cancellable = cancellable
        self.noteToken = noteToken
    }

    deinit {
        cancellable.cancel()
        NotificationCenter.default.removeObserver(noteToken)
    }
}
#endif

/// Coalesces rapid observation callbacks into one MainActor pass via ``HostClock``.
@MainActor
private final class QueryRefreshCoalescer {
    private weak var application: Application?
    private var workID: HostClock.WorkID?

    init(application: Application?) {
        self.application = application
    }

    func schedule(_ work: @escaping @MainActor () -> Void) {
        if let clock = application?.clock {
            if let id = workID {
                clock.cancel(id)
            }
            workID = clock.schedule(after: 0.016) { [weak self] in
                self?.workID = nil
                work()
            }
            return
        }
        // Headless / no host yet: next MainActor turn.
        Task { @MainActor in
            await Task.yield()
            work()
        }
    }
}

@MainActor
@propertyWrapper
public struct Query<Element: PersistentModel>: AnyState {
    private let descriptor: FetchDescriptor<Element>
    
    // We use StateReference to receive the node injected by View's reflection.
    var valueReference = StateReference()

    func seedInitialValueIfNeeded() {}

    public init(filter: Predicate<Element>? = nil, sort: [SortDescriptor<Element>] = []) {
        self.descriptor = FetchDescriptor(predicate: filter, sortBy: sort)
    }

    public init<Value: Comparable>(
        filter: Predicate<Element>? = nil,
        sort keyPath: any KeyPath<Element, Value> & Sendable,
        order: SortOrder = .forward
    ) {
        self.descriptor = FetchDescriptor(
            predicate: filter,
            sortBy: [SortDescriptor(keyPath, order: order)]
        )
    }

    public init<Value: Comparable>(
        filter: Predicate<Element>? = nil,
        sort keyPath: any KeyPath<Element, Value?> & Sendable,
        order: SortOrder = .forward
    ) {
        self.descriptor = FetchDescriptor(
            predicate: filter,
            sortBy: [SortDescriptor(keyPath, order: order)]
        )
    }

    public init(_ descriptor: FetchDescriptor<Element>) {
        self.descriptor = descriptor
    }

    public var wrappedValue: [Element] {
        get {
            guard let node = valueReference.node,
                  let slot = valueReference.slot else {
                return []
            }

            let envValues = node.resolvedEnvironment()
            guard let context = envValues.modelContext else {
                return []
            }

            let membershipKey = "query.\(slot).membership"
            let coalescerKey = "query.\(slot).coalescer"
            let obsKey = "query.\(slot).obs"
            let descriptor = self.descriptor

            if node.storage[coalescerKey] == nil {
                node.storage[coalescerKey] = QueryRefreshCoalescer(
                    application: node.root.application
                )
            }

            // Setup observation before serving cache so first empty fetch still watches saves.
            if node.storage[obsKey] == nil {
                #if canImport(SwiftData)
                installSwiftDataObserver(
                    node: node,
                    slot: slot,
                    membershipKey: membershipKey,
                    coalescerKey: coalescerKey,
                    obsKey: obsKey,
                    descriptor: descriptor,
                    context: context
                )
                #else
                installJsonDataMembershipObserver(
                    node: node,
                    slot: slot,
                    membershipKey: membershipKey,
                    coalescerKey: coalescerKey,
                    obsKey: obsKey,
                    descriptor: descriptor,
                    context: context
                )
                #endif
            }

            if let cached = node.state[slot] as? [Element] {
                return cached
            }

            let items = (try? context.fetch(descriptor)) ?? []
            node.state[slot] = items
            node.storage[membershipKey] = items.map(\.persistentModelID)
            return items
        }
        nonmutating set {
            // Read-only property wrapper
        }
    }

    #if canImport(SwiftData)
    private func installSwiftDataObserver(
        node: Node,
        slot: Int,
        membershipKey: String,
        coalescerKey: String,
        obsKey: String,
        descriptor: FetchDescriptor<Element>,
        context: ModelContext
    ) {
        // Listen to system didSave — do not invent change lists in save().
        let expectedContainer = ObjectIdentifier(context.container)
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak node] notification in
            let savedContainer = (notification.object as? ModelContext)
                .map { ObjectIdentifier($0.container) }
            guard savedContainer == expectedContainer else { return }

            // Parse on the notification thread with a nonisolated helper — do not
            // call @MainActor Query APIs or send userInfo across isolation.
            let userInfo = notification.userInfo
            let inserted = swiftDataPersistentIdentifiers(
                in: userInfo,
                key: ModelContext.NotificationKey.insertedIdentifiers
            )
            let deleted = swiftDataPersistentIdentifiers(
                in: userInfo,
                key: ModelContext.NotificationKey.deletedIdentifiers
            )
            let updated = swiftDataPersistentIdentifiers(
                in: userInfo,
                key: ModelContext.NotificationKey.updatedIdentifiers
            )
            let hasUserInfo =
                userInfo?[ModelContext.NotificationKey.insertedIdentifiers] != nil
                || userInfo?[ModelContext.NotificationKey.deletedIdentifiers] != nil
                || userInfo?[ModelContext.NotificationKey.updatedIdentifiers] != nil

            Task { @MainActor in
                guard let n = node,
                      let coalescer = n.storage[coalescerKey] as? QueryRefreshCoalescer
                else { return }
                coalescer.schedule {
                    Self.applySwiftDataSave(
                        node: n,
                        slot: slot,
                        membershipKey: membershipKey,
                        descriptor: descriptor,
                        inserted: inserted,
                        deleted: deleted,
                        updated: updated,
                        hasUserInfo: hasUserInfo
                    )
                }
            }
        }
        node.storage[obsKey] = NotificationTokenBox(token)
    }

    private static func applySwiftDataSave(
        node: Node,
        slot: Int,
        membershipKey: String,
        descriptor: FetchDescriptor<Element>,
        inserted: Set<PersistentIdentifier>,
        deleted: Set<PersistentIdentifier>,
        updated: Set<PersistentIdentifier>,
        hasUserInfo: Bool
    ) {
        guard let ctx = node.root.application?.swiftDataContext else { return }

        // Always reconcile membership (same as JsonData). Relying only on
        // `insertedIdentifiers` misses empty→first-row when userInfo is incomplete
        // or the insert is reported as an update on a related model — UI then
        // stays empty until a page remount / resize.
        let newMembership = (try? ctx.fetchIdentifiers(descriptor)) ?? []
        let previous = node.storage[membershipKey] as? [PersistentIdentifier]
        if previous != newMembership {
            let items = (try? ctx.fetch(descriptor)) ?? []
            node.state[slot] = items
            node.storage[membershipKey] = newMembership
            // Row count change → LazyVStack / ScrollView need layout, not just paint.
            node.root.application?.invalidateNode(node, layout: true)
            return
        }

        // Membership unchanged: merge store values into this context, keep the same
        // identifier sequence in cache, then invalidate so row `.equatable()` views
        // refresh. Cross-context SwiftData saves do not reliably fire Observation
        // on already-registered models without a fetch + view pass.
        guard !updated.isEmpty || !hasUserInfo || !inserted.isEmpty || !deleted.isEmpty else {
            return
        }
        let cached = (node.state[slot] as? [Element]) ?? []
        let cachedIDs = Set(cached.map(\.persistentModelID))
        // Empty cache with a no-op membership compare already returned above.
        // For in-place updates, only refresh when the save touches our rows
        // (or userInfo is missing and we must assume relevance).
        if hasUserInfo {
            let relevant = updated.union(inserted).union(deleted).intersection(cachedIDs)
            guard !relevant.isEmpty else { return }
        }

        let items = (try? ctx.fetch(descriptor)) ?? cached
        node.state[slot] = items
        node.storage[membershipKey] = items.map(\.persistentModelID)
        node.root.application?.invalidateNode(node)
    }
    #else
    private func installJsonDataMembershipObserver(
        node: Node,
        slot: Int,
        membershipKey: String,
        coalescerKey: String,
        obsKey: String,
        descriptor: FetchDescriptor<Element>,
        context: ModelContext
    ) {
        let contextKey = "query.\(slot).ctx"
        node.storage[contextKey] = context

        let scheduleRefresh: @MainActor (Node) -> Void = { n in
            guard let coalescer = n.storage[coalescerKey] as? QueryRefreshCoalescer else { return }
            coalescer.schedule {
                Self.applyJsonDataMembership(
                    node: n,
                    slot: slot,
                    membershipKey: membershipKey,
                    contextKey: contextKey,
                    descriptor: descriptor
                )
            }
        }

        let cancellable = AnyDatabaseCancellable(
            context.startMembershipObservation(
                descriptor,
                onError: { _ in },
                onChange: { [weak node] _ in
                    Task { @MainActor in
                        guard let n = node else { return }
                        scheduleRefresh(n)
                    }
                }
            )
        )

        // ValueObservation 只看已 commit 的 DB；save 后的 contextDidChange 再兜一层。
        // fetch(descriptor) 含 pending delete，删除后未 autosave 前也能立刻刷新。
        // queue 必须为 nil：corelibs-foundation 的 post() 对指定 queue 的观察者会
        // addOperation + waitUntilAllOperationsAreFinished 同步等待；通知本身在主线程
        // 投递时，等待 OperationQueue.main 即等待自己 → 主线程永久死锁（发送即卡死）。
        // block 内已用 Task { @MainActor } 跳回主线程，语义不变。
        let noteToken = NotificationCenter.default.addObserver(
            forName: ModelContext.contextDidChange,
            object: nil,
            queue: nil
        ) { [weak node] _ in
            Task { @MainActor in
                guard let n = node else { return }
                scheduleRefresh(n)
            }
        }

        node.storage[obsKey] = JsonDataQueryObservationBox(
            cancellable: cancellable,
            noteToken: noteToken
        )

        // 首次挂载后若已有 pending 变更，立刻对齐缓存。
        if context.hasChanges {
            scheduleRefresh(node)
        }
    }

    private static func applyJsonDataMembership(
        node: Node,
        slot: Int,
        membershipKey: String,
        contextKey: String,
        descriptor: FetchDescriptor<Element>
    ) {
        guard let ctx = node.storage[contextKey] as? ModelContext else { return }

        // includePendingChanges=true：本地 delete 未 save 也能从结果集消失。
        let items = (try? ctx.fetch(descriptor)) ?? []
        let newMembership = items.map(\.persistentModelID)
        let previous = node.storage[membershipKey] as? [PersistentIdentifier]

        if previous != newMembership {
            node.state[slot] = items
            node.storage[membershipKey] = newMembership
            // ForEach 行数变化需要 layout，否则 LazyVStack/ScrollView 尺寸滞后。
            node.root.application?.invalidateNode(node, layout: true)
            return
        }

        // ID 列表不变：刷新已缓存模型字段（行内 UPDATE）。
        if let cached = node.state[slot] as? [Element] {
            ctx.refreshCachedModels(ids: cached.map(\.persistentModelID))
            node.state[slot] = items
        }
    }
    #endif
}
