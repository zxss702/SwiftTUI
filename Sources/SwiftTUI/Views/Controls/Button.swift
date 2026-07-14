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
        let control = ButtonElement(action: action, hover: hover)
        control.label = node.children[0].element(at: 0)
        control.addSubview(control.label, at: 0)
        control.onActivate = makeOnActivate()
        node.element = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        node.children[0].update(using: label.view)
        let control = node.element as! ButtonElement
        let newLabel = node.children[0].element(at: 0)
        control.label = newLabel
        control.syncChild(newLabel)
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

    private class ButtonElement: Element {
        var action: () -> Void
        var hover: () -> Void
        var onActivate: (() -> Void)?
        var label: Element!
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
            guard highlighted else { return }
            // VT path: `buffer.cell(at:)` is always nil — swap fg/bg on the back buffer.
            if let vt = buffer.vtRenderer {
                let origin = buffer.translation
                for y in 0 ..< frame.size.height.intValue {
                    for x in 0 ..< frame.size.width.intValue {
                        let abs = Position(
                            column: Extended(x) + origin.column,
                            line: Extended(y) + origin.line
                        )
                        let vtPos = VTPosition(row: abs.line.intValue + 1, column: abs.column.intValue + 1)
                        let cell = vt.back[vtPos]
                        vt.back[vtPos] = VTCell(
                            character: cell.character,
                            style: VTStyle(
                                foreground: cell.style.background,
                                background: cell.style.foreground,
                                attributes: cell.style.attributes
                            )
                        )
                    }
                }
                return
            }
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
