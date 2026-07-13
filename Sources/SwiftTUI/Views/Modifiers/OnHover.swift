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
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let onHoverControl = control.parent as? OnHoverControl {
            onHoverControl.action = action
            return onHoverControl
        }
        let onHoverControl = OnHoverControl(action: action)
        onHoverControl.addSubview(control, at: 0)
        return onHoverControl
    }

    private final class OnHoverControl: Control {
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
            action(isHovered)
        }
    }
}
