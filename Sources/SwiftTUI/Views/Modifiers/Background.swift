import Foundation

public extension View {
    func background(_ color: Color) -> some View {
        return Background(content: self, color: color)
    }
}

private struct Background<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let color: Color

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! BackgroundElement
            if control.color != color {
                control.color = color
                control.layer.invalidate()
            }
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let backgroundElement = control.parent as? BackgroundElement {
            backgroundElement.color = color
            return backgroundElement
        }
        let backgroundElement = BackgroundElement(color: color)
        backgroundElement.addSubview(control, at: 0)
        node.elements?.add(backgroundElement)
        return backgroundElement
    }

    private class BackgroundElement: Element {
        var color: Color

        override var donatesDescendantPointerOnClick: Bool { true }

        init(color: Color) {
            self.color = color
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func draw(into buffer: inout ScreenBuffer) {
            let cell = Cell(char: " ", backgroundColor: color)
            for y in 0 ..< layer.frame.size.height.intValue {
                for x in 0 ..< layer.frame.size.width.intValue {
                    buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                }
            }
        }
    }
}
