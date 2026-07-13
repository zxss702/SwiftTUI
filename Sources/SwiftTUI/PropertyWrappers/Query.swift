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
            
            // Setup observation before serving cache so first empty fetch still watches saves.
            let obsKey = "\(label)_obs"
            let descriptor = self.descriptor
            if node.state[obsKey] == nil {
                #if canImport(SwiftData)
                // Apple SwiftData: Logorythia writes via mainContext / ModelActor, not the
                // TUI frame flush. Watch every save on this container, then refetch.
                // Do not capture ModelContext into the @Sendable notification/Task closures.
                let expectedContainer = ObjectIdentifier(context.container)
                let token = NotificationCenter.default.addObserver(
                    forName: ModelContext.didSave,
                    object: nil,
                    queue: nil
                ) { [weak node] notification in
                    let savedContainer = (notification.object as? ModelContext)
                        .map { ObjectIdentifier($0.container) }
                    guard savedContainer == expectedContainer else { return }
                    Task { @MainActor in
                        guard let n = node,
                              let ctx = n.root.application?.swiftDataContext
                        else { return }
                        let updatedItems = (try? ctx.fetch(descriptor)) ?? []
                        n.state[label] = updatedItems
                        n.root.application?.invalidateNode(n)
                    }
                }
                node.state[obsKey] = NotificationTokenBox(token)
                #else
                // JsonData/GRDB: ValueObservation across writers on the shared queue.
                let task = context.startObservation(
                    descriptor,
                    onError: { _ in },
                    onChange: { [weak node] newItems in
                        Task { @MainActor in
                            guard let n = node else { return }
                            n.state[label] = newItems
                            n.root.application?.invalidateNode(n)
                        }
                    }
                )
                node.state[obsKey] = task
                #endif
            }

            if let cached = node.state[label] as? [Element] {
                return cached
            }

            let items = (try? context.fetch(descriptor)) ?? []
            node.state[label] = items
            return items
        }
        nonmutating set {
            // Read-only property wrapper
        }
    }
}
