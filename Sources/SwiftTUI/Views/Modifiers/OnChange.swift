import Foundation

public extension View {
    /// 当 `value` 变化时调用；`initial == true` 时在首次出现也调用一次。
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
        node.state["onChange.previous"] = value
        node.state["onChange.didInitial"] = false
        if initial {
            let action = self.action
            let value = self.value
            DispatchQueue.main.async {
                action(value, value)
            }
            node.state["onChange.didInitial"] = true
        }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let previous = node.state["onChange.previous"] as? V
        if let previous, previous != value {
            let action = self.action
            let newValue = value
            DispatchQueue.main.async {
                action(previous, newValue)
            }
        } else if initial, (node.state["onChange.didInitial"] as? Bool) != true {
            let action = self.action
            let value = self.value
            DispatchQueue.main.async {
                action(value, value)
            }
            node.state["onChange.didInitial"] = true
        }
        node.state["onChange.previous"] = value
    }
}
