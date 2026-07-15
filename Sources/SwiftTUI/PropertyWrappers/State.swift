import Foundation

@propertyWrapper
@MainActor public struct State<T>: AnyState {
    public let initialValue: T

    public init(initialValue: T) {
        self.initialValue = initialValue
    }

    public init(wrappedValue: T) {
        self.initialValue = wrappedValue
    }

    /// `@State` stores its value in the owning ViewGraph node (slot-based).
    var valueReference = StateReference()

    public var wrappedValue: T {
        get {
            guard let node = valueReference.node,
                  let slot = valueReference.slot
            else {
                return initialValue
            }
            if let value = node.state[slot] {
                return value as! T
            }
            node.state[slot] = initialValue
            return initialValue
        }
        nonmutating set {
            setValue(newValue, invalidate: true)
        }
    }

    /// Framework use: write state without scheduling a node invalidation.
    nonmutating func setValue(_ newValue: T, invalidate: Bool) {
        guard let node = valueReference.node,
              let slot = valueReference.slot
        else {
            return
        }
        // SwiftUI-shaped: writing an equal value must not re-render.
        // (onHover rows fire `hovering = true` on every move — without this
        // the row rebuilds per move and hover tracking dangles.)
        if let old = node.state[slot] as? T, StateEquality.areEqual(old, newValue) {
            node.state[slot] = newValue
            return
        }
        node.state[slot] = newValue
        if invalidate {
            node.root.application?.invalidateNode(node)
        }
    }

    public var projectedValue: Binding<T> {
        let reference = valueReference
        let fallback = initialValue
        return Binding<T>(
            get: {
                guard let node = reference.node, let slot = reference.slot else {
                    return fallback
                }
                if let value = node.state[slot] as? T {
                    return value
                }
                node.state[slot] = fallback
                return fallback
            },
            set: { newValue in
                guard let node = reference.node, let slot = reference.slot else {
                    return
                }
                // Same equal-value skip as `setValue` (Binding writes).
                if let old = node.state[slot] as? T, StateEquality.areEqual(old, newValue) {
                    node.state[slot] = newValue
                    return
                }
                node.state[slot] = newValue
                node.root.application?.invalidateNode(node)
            }
        )
    }

    func seedInitialValueIfNeeded() {
        guard let node = valueReference.node,
              let slot = valueReference.slot,
              node.state[slot] == nil
        else { return }
        node.state[slot] = initialValue
    }
}

@MainActor protocol AnyState {
    var valueReference: StateReference { get }
    func seedInitialValueIfNeeded()
}

@MainActor final class StateReference {
    weak var node: Node?
    /// Declaration-order slot within the owning node (not Mirror label).
    var slot: Int?
}
