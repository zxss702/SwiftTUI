import Foundation

public extension View {
    func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        OnTapGestureModifier(content: self, count: max(1, count), action: action)
    }
}

@MainActor
private struct OnTapGestureModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let count: Int
    let action: () -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            let control = control as! OnTapGestureControl
            control.count = count
            control.action = action
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? OnTapGestureControl {
            existing.count = count
            existing.action = action
            return existing
        }
        let wrapper = OnTapGestureControl(count: count, action: action)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }

    private final class OnTapGestureControl: Control {
        var count: Int
        var action: () -> Void
        private var taps = 0
        private var resetWork: DispatchWorkItem?

        init(count: Int, action: @escaping () -> Void) {
            self.count = count
            self.action = action
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hitTest(position: Position) -> Control? {
            let local = position - layer.frame.position
            guard local.column >= 0, local.line >= 0,
                  local.column < layer.frame.size.width,
                  local.line < layer.frame.size.height else {
                return nil
            }
            // 整块区域由本控件接收 tap（子视图装饰不抢事件）
            return self
        }

        override func handleMouseEvent(_ event: MouseEvent) {
            if case .released(.left) = event.type {
                taps += 1
                resetWork?.cancel()
                if taps >= count {
                    taps = 0
                    action()
                } else {
                    let work = DispatchWorkItem { [weak self] in self?.taps = 0 }
                    resetWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                }
            } else {
                super.handleMouseEvent(event)
            }
        }
    }
}
