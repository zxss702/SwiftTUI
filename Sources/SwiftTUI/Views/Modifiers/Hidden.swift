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
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            let control = control as! HiddenControl
            control.isHidden = isHidden
            control.layer.invalidate()
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? HiddenControl {
            existing.isHidden = isHidden
            return existing
        }
        let wrapper = HiddenControl(isHidden: isHidden)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }

    private final class HiddenControl: Control {
        var isHidden: Bool

        init(isHidden: Bool) {
            self.isHidden = isHidden
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hitTest(position: Position) -> Control? {
            isHidden ? nil : super.hitTest(position: position)
        }

        override func makeLayer() -> Layer {
            HiddenLayer(isHidden: { [weak self] in self?.isHidden ?? false })
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
