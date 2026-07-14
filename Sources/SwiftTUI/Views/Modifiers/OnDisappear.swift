import Foundation

public extension View {
    /// 视图从层级中移除时调用（控件被拆下时）。
    func onDisappear(_ action: @escaping () -> Void) -> some View {
        OnDisappear(content: self, action: action)
    }
}

@MainActor
private struct OnDisappear<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let action: () -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! OnDisappearElement).action = action
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? OnDisappearElement {
            existing.action = action
            return existing
        }
        let wrapper = OnDisappearElement(action: action)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }
}

@MainActor
final class OnDisappearElement: Element {
    var action: () -> Void
    private var didDisappear = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    override func size(proposedSize: Size) -> Size {
        children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children[0].layout(size: size)
    }

    override func willRemoveFromParent() {
        if !didDisappear {
            didDisappear = true
            // Sync — same rule as onAppear: deferred GCD made chrome/state one-behind.
            action()
        }
        super.willRemoveFromParent()
    }
}
