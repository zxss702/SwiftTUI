import Foundation

public extension View {
    /// 当 `value` 变化时调用；`initial == true` 时在首次出现也调用一次。
    /// 在当前 settle 的 `updateNode` 中同步触发（不用 GCD 延迟）。
    func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        OnChange(content: self, value: value, initial: initial, action: action)
    }

    func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        onChange(of: value, initial: initial) { _, _ in action() }
    }
}

@MainActor
private struct OnChange<Content: View, V: Equatable>: View, PrimitiveView {
    let content: Content
    let value: V
    let initial: Bool
    let action: (V, V) -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.storage["onChange.previous"] = value
        node.storage["onChange.didInitial"] = false
        if initial {
            // Always the action from this build — never a stale captured handler.
            action(value, value)
            node.storage["onChange.didInitial"] = true
        }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        // Read `action` / `value` from `self` after `node.view = self` so the
        // handler always matches the latest View value (not a prior closure).
        let fire = action
        let newValue = value
        let previous = node.storage["onChange.previous"] as? V
        if let previous, previous != newValue {
            fire(previous, newValue)
        } else if initial, (node.storage["onChange.didInitial"] as? Bool) != true {
            fire(newValue, newValue)
            node.storage["onChange.didInitial"] = true
        }
        node.storage["onChange.previous"] = newValue
    }
}
