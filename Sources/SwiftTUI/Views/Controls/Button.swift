import Foundation

@MainActor public struct Button<Label: View>: View, PrimitiveView {
    let label: VStack<Label>
    let hover: () -> Void
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.buttonDismissesPresentation) private var buttonDismissesPresentation

    public init(action: @escaping () -> Void, hover: @escaping () -> Void = {}, @ViewBuilder label: () -> Label) {
        self.label = VStack(content: label())
        self.action = action
        self.hover = hover
    }

    public init(_ text: String, hover: @escaping () -> Void = {}, action: @escaping () -> Void) where Label == Text {
        self.label = VStack(content: Text(text))
        self.action = action
        self.hover = hover
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.addNode(at: 0, Node(view: label.view))
        let control = ButtonControl(action: action, hover: hover)
        control.label = node.children[0].control(at: 0)
        control.addSubview(control.label, at: 0)
        control.onActivate = makeOnActivate()
        node.control = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        node.children[0].update(using: label.view)
        let control = node.control as! ButtonControl
        control.action = action
        control.hover = hover
        control.onActivate = makeOnActivate()
    }

    private func makeOnActivate() -> () -> Void {
        let action = self.action
        let dismiss = self.dismiss
        let autoDismiss = buttonDismissesPresentation
        return {
            action()
            if autoDismiss {
                dismiss()
            }
        }
    }

    private class ButtonControl: Control {
        var action: () -> Void
        var hover: () -> Void
        var onActivate: (() -> Void)?
        var label: Control!
        weak var buttonLayer: ButtonLayer?

        init(action: @escaping () -> Void, hover: @escaping () -> Void) {
            self.action = action
            self.hover = hover
        }

        override var selectable: Bool { true }

        override func size(proposedSize: Size) -> Size {
            return label.size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            self.label.layout(size: size)
        }

        override func handleEvent(_ char: Character) {
            if char == "\n" || char == " " {
                performAction()
            }
        }

        override func handleMouseEvent(_ event: MouseEvent) {
            if case .released(.left) = event.type {
                performAction()
            } else {
                super.handleMouseEvent(event)
            }
        }

        private func performAction() {
            if let onActivate {
                onActivate()
            } else {
                action()
            }
        }

        override func hoveredStateDidChange() {
            buttonLayer?.highlighted = isHovered
            if isHovered { hover() }
            layer.invalidate()
        }

        override func makeLayer() -> Layer {
            let layer = ButtonLayer()
            self.buttonLayer = layer
            return layer
        }
    }

    private class ButtonLayer: Layer {
        var highlighted = false

        override func draw(into buffer: inout ScreenBuffer) {
            super.draw(into: &buffer)
            if highlighted {
                for y in 0 ..< frame.size.height.intValue {
                    for x in 0 ..< frame.size.width.intValue {
                        let pos = Position(column: Extended(x), line: Extended(y))
                        if var cell = buffer.cell(at: pos) {
                            cell.attributes.inverted.toggle()
                            buffer.setCell(cell, at: pos)
                        }
                    }
                }
            }
        }
    }
}
