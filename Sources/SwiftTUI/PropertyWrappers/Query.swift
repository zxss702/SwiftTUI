import Foundation
#if canImport(SwiftData)
import SwiftData
#else
import JsonData
import GRDB

public typealias Predicate<T: PersistentModel> = JsonDataCore.Predicate<T>
public typealias SortDescriptor<T: PersistentModel> = JsonDataCore.SortDescriptor<T>
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
    private let filter: Predicate<Element>?
    private let sort: [SortDescriptor<Element>]
    
    // We use StateReference to receive the node injected by View's reflection.
    var valueReference = StateReference()

    public init(filter: Predicate<Element>? = nil, sort: [SortDescriptor<Element>] = []) {
        self.filter = filter
        self.sort = sort
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
            
            // 1. If we already have items cached in node.state, return them
            if let cached = node.state[label] as? [Element] {
                return cached
            }
            
            // 2. Initial fetch and store in node.state (imitating @State)
            let descriptor = FetchDescriptor<Element>(predicate: filter, sortBy: sort)
            let items = (try? context.fetch(descriptor)) ?? []
            node.state[label] = items
            
            // 3. Setup observation (only once per node property)
            let obsKey = "\(label)_obs"
            if node.state[obsKey] == nil {
                #if canImport(SwiftData)
                // macOS SwiftData: Use Application observer
                node.root.application?.swiftDataObservers.append { [weak node] in
                    guard let n = node else { return }
                    let updatedItems = (try? context.fetch(descriptor)) ?? []
                    n.state[label] = updatedItems
                    n.root.application?.invalidateNode(n)
                }
                node.state[obsKey] = true
                #else
                // Linux JsonData/GRDB: Use startObservation
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
            
            return items
        }
        nonmutating set {
            // Read-only property wrapper
        }
    }
}
