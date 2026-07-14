import Foundation

public extension View {
    /// 在视图首次出现时调用。始终在主线程执行。
    func onAppear(_ action: @escaping () -> Void) -> some View {
        OnAppear(content: self, action: action)
    }
}

private struct OnAppear<Content: View>: View, PrimitiveView, ModifierView {
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
            (control as! OnAppearElement).action = action
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let onAppearElement = control.parent as? OnAppearElement {
            onAppearElement.action = action
            return onAppearElement
        }
        let onAppearElement = OnAppearElement(action: action)
        onAppearElement.addSubview(control, at: 0)
        node.elements?.add(onAppearElement)
        return onAppearElement
    }

    private class OnAppearElement: Element {
        var action: () -> Void
        var didAppear = false

        init(action: @escaping () -> Void) {
            self.action = action
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
            if !didAppear {
                didAppear = true
                // Synchronous: `DispatchQueue.main.async` deferred title/toolbar/state
                // until a later turn, which felt like "next click paints previous action".
                action()
            }
        }
    }
}
