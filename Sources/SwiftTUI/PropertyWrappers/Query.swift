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

/// Coalesces rapid observation callbacks into one MainActor pass.
@MainActor
private final class QueryRefreshCoalescer {
    private var pending: Task<Void, Never>?

    func schedule(_ work: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
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
                  let label = valueReference.label else {
                return []
            }
            
            // Build environment to get the ModelContext
            var envValues = EnvironmentValues()
            var current: Node? = node
            
            var transforms: [(inout EnvironmentValues) -> Void] = []
            while let c = current {
                if let t = c.environment {
                    transforms.insert(t, at: 0)
                }
                current = c.parent
            }
            for t in transforms {
                t(&envValues)
            }
            
            guard let context = envValues.modelContext else {
                return []
            }
            
            let membershipKey = "\(label)_membership"
            let coalescerKey = "\(label)_coalescer"
            let obsKey = "\(label)_obs"
            let descriptor = self.descriptor

            if node.state[coalescerKey] == nil {
                node.state[coalescerKey] = QueryRefreshCoalescer()
            }

            // Setup observation before serving cache so first empty fetch still watches saves.
            if node.state[obsKey] == nil {
                #if canImport(SwiftData)
                installSwiftDataObserver(
                    node: node,
                    label: label,
                    membershipKey: membershipKey,
                    coalescerKey: coalescerKey,
                    obsKey: obsKey,
                    descriptor: descriptor,
                    context: context
                )
                #else
                installJsonDataMembershipObserver(
                    node: node,
                    label: label,
                    membershipKey: membershipKey,
                    coalescerKey: coalescerKey,
                    obsKey: obsKey,
                    descriptor: descriptor,
                    context: context
                )
                #endif
            }

            if let cached = node.state[label] as? [Element] {
                return cached
            }

            let items = (try? context.fetch(descriptor)) ?? []
            node.state[label] = items
            node.state[membershipKey] = items.map(\.persistentModelID)
            return items
        }
        nonmutating set {
            // Read-only property wrapper
        }
    }

    #if canImport(SwiftData)
    private func installSwiftDataObserver(
        node: Node,
        label: String,
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
                      let coalescer = n.state[coalescerKey] as? QueryRefreshCoalescer
                else { return }
                coalescer.schedule {
                    Self.applySwiftDataSave(
                        node: n,
                        label: label,
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
        node.state[obsKey] = NotificationTokenBox(token)
    }

    private static func applySwiftDataSave(
        node: Node,
        label: String,
        membershipKey: String,
        descriptor: FetchDescriptor<Element>,
        inserted: Set<PersistentIdentifier>,
        deleted: Set<PersistentIdentifier>,
        updated: Set<PersistentIdentifier>,
        hasUserInfo: Bool
    ) {
        guard let ctx = node.root.application?.swiftDataContext else { return }

        let membershipMayChange = !hasUserInfo || !inserted.isEmpty || !deleted.isEmpty
        if membershipMayChange {
            let newMembership = (try? ctx.fetchIdentifiers(descriptor)) ?? []
            let previous = node.state[membershipKey] as? [PersistentIdentifier]
            if previous != newMembership {
                let items = (try? ctx.fetch(descriptor)) ?? []
                node.state[label] = items
                node.state[membershipKey] = newMembership
                node.root.application?.invalidateNode(node)
                return
            }
        }

        // Membership unchanged: merge store values into this context, keep the same
        // identifier sequence in cache, then invalidate so row `.equatable()` views
        // refresh. Cross-context SwiftData saves do not reliably fire Observation
        // on already-registered models without a fetch + view pass.
        guard !updated.isEmpty || !hasUserInfo else { return }
        let cached = (node.state[label] as? [Element]) ?? []
        let cachedIDs = Set(cached.map(\.persistentModelID))
        let relevant = hasUserInfo ? updated.intersection(cachedIDs) : cachedIDs
        guard !relevant.isEmpty else { return }

        let items = (try? ctx.fetch(descriptor)) ?? cached
        let newMembership = items.map(\.persistentModelID)
        if let previous = node.state[membershipKey] as? [PersistentIdentifier],
           previous != newMembership
        {
            node.state[label] = items
            node.state[membershipKey] = newMembership
            node.root.application?.invalidateNode(node)
            return
        }

        // Same membership: replace element refs so ForEach can push updates;
        // MarkdownView.equatable() skips unchanged content.
        node.state[label] = items
        node.state[membershipKey] = newMembership
        node.root.application?.invalidateNode(node)
    }
    #else
    private func installJsonDataMembershipObserver(
        node: Node,
        label: String,
        membershipKey: String,
        coalescerKey: String,
        obsKey: String,
        descriptor: FetchDescriptor<Element>,
        context: ModelContext
    ) {
        let contextKey = "\(label)_ctx"
        node.state[contextKey] = context

        let scheduleRefresh: @MainActor (Node) -> Void = { n in
            guard let coalescer = n.state[coalescerKey] as? QueryRefreshCoalescer else { return }
            coalescer.schedule {
                Self.applyJsonDataMembership(
                    node: n,
                    label: label,
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
        let noteToken = NotificationCenter.default.addObserver(
            forName: ModelContext.contextDidChange,
            object: nil,
            queue: .main
        ) { [weak node] _ in
            Task { @MainActor in
                guard let n = node else { return }
                scheduleRefresh(n)
            }
        }

        node.state[obsKey] = JsonDataQueryObservationBox(
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
        label: String,
        membershipKey: String,
        contextKey: String,
        descriptor: FetchDescriptor<Element>
    ) {
        guard let ctx = node.state[contextKey] as? ModelContext else { return }

        // includePendingChanges=true：本地 delete 未 save 也能从结果集消失。
        let items = (try? ctx.fetch(descriptor)) ?? []
        let newMembership = items.map(\.persistentModelID)
        let previous = node.state[membershipKey] as? [PersistentIdentifier]

        if previous != newMembership {
            node.state[label] = items
            node.state[membershipKey] = newMembership
            // ForEach 行数变化需要 layout，否则 LazyVStack/ScrollView 尺寸滞后。
            node.root.application?.invalidateNode(node, layout: true)
            return
        }

        // ID 列表不变：刷新已缓存模型字段（行内 UPDATE）。
        if let cached = node.state[label] as? [Element] {
            ctx.refreshCachedModels(ids: cached.map(\.persistentModelID))
            node.state[label] = items
        }
    }
    #endif
}
