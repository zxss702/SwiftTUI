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
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! OnTapGestureElement
            control.count = count
            control.action = action
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? OnTapGestureElement {
            existing.count = count
            existing.action = action
            return existing
        }
        let wrapper = OnTapGestureElement(count: count, action: action)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class OnTapGestureElement: Element {
        var count: Int
        var action: () -> Void
        private var taps = 0
        private var resetWorkID: HostClock.WorkID?

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

        override func hitTest(position: Position) -> Element? {
            let local = position - layer.frame.position
            guard local.column >= 0, local.line >= 0,
                  local.column < layer.frame.size.width,
                  local.line < layer.frame.size.height else {
                return nil
            }
            // 整块区域由本控件接收 tap（子视图装饰不抢事件）
            return self
        }

        override func dispatchMouseEvent(_ event: MouseEvent) -> Bool {
            guard absoluteFrame.contains(event.position) else { return false }
            return consumeMouseEvent(event)
        }

        private var countedThisGesture = false

        override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
            guard event.button == .left else { return false }
            switch event.phase {
            case .began:
                guard !countedThisGesture else { return true }
                countedThisGesture = true
                registerTap()
                return true
            case .ended, .cancelled:
                if event.phase == .ended, !countedThisGesture {
                    registerTap()
                }
                countedThisGesture = false
                return true
            case .moved:
                return countedThisGesture
            }
        }

        override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
            false
        }

        private func registerTap() {
            taps += 1
            cancelReset()
            if taps >= count {
                taps = 0
                action()
            } else if let clock = layer.rootRenderer?.application?.clock {
                resetWorkID = clock.schedule(after: 0.3) { [weak self] in
                    self?.taps = 0
                    self?.resetWorkID = nil
                }
            } else {
                taps = 0
            }
        }

        private func cancelReset() {
            if let id = resetWorkID {
                layer.rootRenderer?.application?.clock.cancel(id)
                resetWorkID = nil
            }
        }

        override func willRemoveFromParent() {
            cancelReset()
            super.willRemoveFromParent()
        }
    }
}
