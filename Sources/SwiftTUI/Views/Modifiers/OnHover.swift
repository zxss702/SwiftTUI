import Foundation

public extension View {
    /// 鼠标进入/离开时回调。在 MainActor 上调用，可直接改 `@State` 等（对齐 SwiftUI）。
    func onHover(perform action: @escaping @MainActor (Bool) -> Void) -> some View {
        OnHover(content: self, action: action)
    }
}

@MainActor
private struct OnHover<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let action: @MainActor (Bool) -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for element in node.elements?.values ?? [] {
            (element as! OnHoverElement).action = action
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let onHoverElement = control.parent as? OnHoverElement {
            onHoverElement.action = action
            return onHoverElement
        }
        let onHoverElement = OnHoverElement(action: action)
        onHoverElement.addSubview(control, at: 0)
        node.elements?.add(onHoverElement)
        return onHoverElement
    }

    private final class OnHoverElement: Element {
        var action: @MainActor (Bool) -> Void

        init(action: @escaping @MainActor (Bool) -> Void) {
            self.action = action
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hoveredStateDidChange() {
            // SwiftUI: while menu/popover/sheet is presented, only the presented
            // layer delivers onHover; underlying views stay frozen (no true/false).
            let presented = window?.popupPresenter?.isPresented == true
            let inHost: Bool = {
                guard let host = window?.popupPresenter?.top?.hostElement else {
                    // Host not mounted yet — treat every onHover as underlying.
                    return false
                }
                return self === host || isDescendant(of: host)
            }()
            // #region agent log
            DebugSessionLog.write(
                hypothesisId: "H3",
                location: "OnHoverElement.hoveredStateDidChange",
                message: "onHover callback",
                data: [
                    "hovered": isHovered,
                    "suppressed": presented && !inHost,
                ],
                runId: "post-cleanup"
            )
            // #endregion
            if presented && !inHost { return }
            action(isHovered)
            // Ensure leave/enter paints even when the action does not dirty @State
            // (and so Observation would not schedule a frame).
            layer.invalidate()
        }
    }
}
