import Foundation

extension View {
    /// Bind `@State` / `@FocusState` property wrappers to state slots on the node.
    /// Slots are allocated by declaration order (not Mirror labels), matching SwiftUI
    /// structural state identity.
    func setupStateProperties(node: Node) {
        var slot = 0
        for (_, value) in Mirror(reflecting: self).children {
            if let stateValue = value as? AnyState {
                stateValue.valueReference.node = node
                stateValue.valueReference.slot = slot
                stateValue.seedInitialValueIfNeeded()
                slot += 1
            } else if let focusValue = value as? AnyFocusState {
                focusValue.valueReference.node = node
                focusValue.valueReference.slot = slot
                slot += 1
            }
        }
    }
}
