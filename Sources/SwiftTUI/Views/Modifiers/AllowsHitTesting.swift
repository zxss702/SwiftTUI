import Foundation

public extension View {
    func allowsHitTesting(_ enabled: Bool) -> some View {
        AllowsHitTesting(content: self, enabled: enabled)
    }
}

@MainActor
private struct AllowsHitTesting<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let enabled: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! AllowsHitTestingElement).enabled = enabled
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? AllowsHitTestingElement {
            existing.enabled = enabled
            return existing
        }
        let wrapper = AllowsHitTestingElement(enabled: enabled)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class AllowsHitTestingElement: Element {
        var enabled: Bool

        init(enabled: Bool) {
            self.enabled = enabled
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hitTest(position: Position) -> Element? {
            guard enabled else { return nil }
            let local = position - layer.frame.position
            guard local.column >= 0, local.line >= 0,
                  local.column < layer.frame.size.width,
                  local.line < layer.frame.size.height else {
                return nil
            }
            for child in children.reversed() {
                if let hit = child.hitTest(position: local) {
                    return hit
                }
            }
            return nil
        }
    }
}
