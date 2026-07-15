import Foundation

public extension View {
    /// Hit-test children only; if they miss, return `nil` instead of absorbing the
    /// hit as a full-size container. Used by `PopupOverlayHost` so a Menu's
    /// window-sized `ZStack` cannot steal clicks meant for the trigger / items.
    func hitTestPassthrough() -> some View {
        HitTestPassthrough(content: self)
    }
}

@MainActor
private struct HitTestPassthrough<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? HitTestPassthroughElement {
            return existing
        }
        let wrapper = HitTestPassthroughElement()
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class HitTestPassthroughElement: Element {
        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hitTest(position: Position) -> Element? {
            let local = position - layer.frame.position
            guard local.column >= 0, local.line >= 0,
                  local.column < layer.frame.size.width,
                  local.line < layer.frame.size.height
            else {
                return nil
            }
            for child in children.reversed() {
                guard let hit = child.hitTest(position: local) else { continue }
                // `ZStack` returns `self` when its children miss — that ate Menu
                // clicks (log: target ZStackElement, pointer nil). Skip pure
                // container self-hits so the event can fall through.
                if hit === child, !child.claimsPointerCapture, !child.canReceiveFocus {
                    continue
                }
                return hit
            }
            return nil
        }

        override func dispatchMouseEvent(_ event: MouseEvent) -> Bool {
            // Never absorb at this wrapper — only children may claim.
            for child in children.reversed() {
                if child.dispatchMouseEvent(event) { return true }
            }
            return false
        }
    }
}
