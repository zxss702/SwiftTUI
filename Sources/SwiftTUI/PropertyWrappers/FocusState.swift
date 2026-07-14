import Foundation

@propertyWrapper
@MainActor public struct FocusState<Value: Hashable>: AnyFocusState {
    let resetValue: Value
    var valueReference = FocusStateReference()

    public init() where Value == Bool {
        self.resetValue = false
    }

    public init<T>() where Value == T?, T: Hashable {
        self.resetValue = nil
    }

    public var wrappedValue: Value {
        get { readValue() }
        nonmutating set { writeValue(newValue) }
    }

    public var projectedValue: Binding {
        let reference = valueReference
        let reset = resetValue
        return Binding(
            get: {
                Self.read(reference: reference, reset: reset)
            },
            set: { newValue in
                Self.write(newValue, reference: reference, reset: reset)
            },
            reference: reference,
            resetValue: resetValue
        )
    }

    private func readValue() -> Value {
        Self.read(reference: valueReference, reset: resetValue)
    }

    private func writeValue(_ newValue: Value) {
        Self.write(newValue, reference: valueReference, reset: resetValue)
    }

    private static func read(reference: FocusStateReference, reset: Value) -> Value {
        guard let node = reference.node, let slot = reference.slot else {
            return reset
        }
        if let value = node.state[slot] as? Value {
            return value
        }
        node.state[slot] = reset
        return reset
    }

    private static func write(_ newValue: Value, reference: FocusStateReference, reset: Value) {
        guard let node = reference.node, let slot = reference.slot else {
            assertionFailure("Attempting to modify @FocusState before view is instantiated")
            return
        }
        let previous = (node.state[slot] as? Value) ?? reset
        guard previous != newValue else { return }
        node.state[slot] = newValue
        node.root.application?.invalidateNode(node)
        if !FocusSystem.isSyncing {
            FocusSystem.apply(
                reference: reference,
                value: newValue,
                unfocusedValue: reset,
                window: node.root.application?.window
            )
        }
    }
}

extension FocusState {
    /// Aligns with SwiftUI.FocusState.Binding.
    @propertyWrapper
    @MainActor public struct Binding {
        let get: () -> Value
        let set: (Value) -> Void
        let reference: FocusStateReference
        let resetValue: Value

        public var wrappedValue: Value {
            get { get() }
            nonmutating set { set(newValue) }
        }

        public var projectedValue: Binding { self }
    }
}

@MainActor protocol AnyFocusState {
    var valueReference: FocusStateReference { get }
}

@MainActor final class FocusStateReference {
    weak var node: Node?
    var slot: Int?
}

// MARK: - Focus system

@MainActor
enum FocusSystem {
    static var isSyncing = false

    private static var registrations: [ObjectIdentifier: [FocusRegistration]] = [:]

    static func register(_ registration: FocusRegistration) {
        let key = ObjectIdentifier(registration.reference)
        var list = registrations[key] ?? []
        list.removeAll { $0 === registration || $0.element == nil }
        list.append(registration)
        registrations[key] = list
    }

    static func unregister(_ registration: FocusRegistration) {
        let key = ObjectIdentifier(registration.reference)
        registrations[key]?.removeAll { $0 === registration }
        if registrations[key]?.isEmpty == true {
            registrations[key] = nil
        }
    }

    static func apply<Value: Hashable>(
        reference: FocusStateReference,
        value: Value,
        unfocusedValue: Value,
        window: Window?
    ) {
        guard let window else { return }
        let key = ObjectIdentifier(reference)
        let list = (registrations[key] ?? []).filter { $0.element != nil }

        if let match = list.first(where: { $0.matches(value) }),
           let target = match.targetElement
        {
            window.setFirstResponder(target)
            return
        }

        if value == unfocusedValue,
           let current = window.firstResponder,
           let reg = current.focusRegistration,
           reg.reference === reference
        {
            let fallback = window.elements.first?.firstSelectableElement
            if fallback === current {
                window.setFirstResponder(nil)
            } else {
                window.setFirstResponder(fallback)
            }
        }
    }
}

@MainActor
final class FocusRegistration {
    let reference: FocusStateReference
    weak var element: Element?
    private let match: (Any) -> Bool
    private let writeFocused: () -> Void
    private let writeUnfocused: () -> Void

    init(
        reference: FocusStateReference,
        control: Element,
        match: @escaping (Any) -> Bool,
        writeFocused: @escaping () -> Void,
        writeUnfocused: @escaping () -> Void
    ) {
        self.reference = reference
        self.element = control
        self.match = match
        self.writeFocused = writeFocused
        self.writeUnfocused = writeUnfocused
    }

    var targetElement: Element? { element }

    func matches(_ value: Any) -> Bool {
        match(value)
    }

    func notifyBecomeFirstResponder() {
        FocusSystem.isSyncing = true
        writeFocused()
        FocusSystem.isSyncing = false
    }

    func notifyResignFirstResponder() {
        FocusSystem.isSyncing = true
        writeUnfocused()
        FocusSystem.isSyncing = false
    }
}
