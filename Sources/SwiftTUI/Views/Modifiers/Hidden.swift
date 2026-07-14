import Foundation

public extension View {
    /// 隐藏视图但仍占位（对齐 SwiftUI）。
    func hidden(_ hidden: Bool = true) -> some View {
        HiddenModifier(content: self, isHidden: hidden)
    }
}

@MainActor
private struct HiddenModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let isHidden: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! HiddenElement).isHidden = isHidden
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? HiddenElement {
            existing.isHidden = isHidden
            return existing
        }
        let wrapper = HiddenElement(isHidden: isHidden)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class HiddenElement: Element {
        var isHidden: Bool {
            didSet {
                if isHidden != oldValue {
                    resignFocusIfNeeded()
                    layer.invalidate()
                }
            }
        }

        init(isHidden: Bool) {
            self.isHidden = isHidden
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
            resignFocusIfNeeded()
        }

        /// Keep-alive navigation pages stay mounted; hidden pages must not keep focus
        /// or appear in tab/first-responder walks.
        override var firstSelectableElement: Element? {
            isHidden ? nil : super.firstSelectableElement
        }

        override func hitTest(position: Position) -> Element? {
            isHidden ? nil : super.hitTest(position: position)
        }

        override func makeLayer() -> Layer {
            HiddenLayer(isHidden: { [weak self] in self?.isHidden ?? false })
        }

        private func resignFocusIfNeeded() {
            guard isHidden, let window = root.window else { return }
            window.resignInteraction(in: self)
        }
    }

    private final class HiddenLayer: Layer {
        let isHidden: () -> Bool

        init(isHidden: @escaping () -> Bool) {
            self.isHidden = isHidden
        }

        override func draw(into buffer: inout ScreenBuffer) {
            guard !isHidden() else { return }
            super.draw(into: &buffer)
        }
    }
}
