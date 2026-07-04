import Foundation
import JsonDataCore
import GRDB

@MainActor
@propertyWrapper
public struct Query<Element: PersistentModel & Sendable>: AnyState {
    private let filter: JsonDataCore.Predicate<Element>?
    private let sort: [JsonDataCore.SortDescriptor<Element>]
    
    // We use StateReference to receive the node injected by View's reflection.
    var valueReference = StateReference()

    // We store the observation task and the current items in an internal reference type
    // so we can mutate it even though Query is a struct (property wrappers in SwiftUI/SwiftTUI are structs).
    private final class QueryStateBox: @unchecked Sendable {
        var isAttached = false
        var items: [Element] = []
        var observationTask: DatabaseCancellable?
    }
    private let box = QueryStateBox()

    public init(filter: JsonDataCore.Predicate<Element>? = nil, sort: [JsonDataCore.SortDescriptor<Element>] = []) {
        self.filter = filter
        self.sort = sort
    }

    public var wrappedValue: [Element] {
        get {
            guard let node = valueReference.node else {
                return []
            }
            
            // Build environment to get the ModelContext
            var envValues = EnvironmentValues()
            var current: Node? = node
            // Accumulate environment transformations from root to this node
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
            
            if !box.isAttached {
                box.isAttached = true
                let descriptor = JsonDataCore.FetchDescriptor(predicate: filter, sortBy: sort)
                box.items = (try? context.fetch(descriptor)) ?? []
                
                box.observationTask = context.startObservation(
                    descriptor,
                    onError: { _ in },
                    onChange: { newItems in
                        Task { @MainActor in
                            self.box.items = newItems
                            node.root.application?.invalidateNode(node)
                        }
                    }
                )
            }
            
            return box.items
        }
        nonmutating set {
            // Read-only
        }
    }
}
