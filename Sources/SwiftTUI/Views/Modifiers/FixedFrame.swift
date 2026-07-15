import Foundation

public extension View {
    // Aligns content to the top leading corner by default.
    func frame(width: Extended? = nil, height: Extended? = nil, alignment: Alignment = .topLeading) -> some View {
        FixedFrame(content: self, width: width, height: height, alignment: alignment)
    }
}

private struct FixedFrame<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let width: Extended?
    let height: Extended?
    let alignment: Alignment

    init(content: Content, width: Extended?, height: Extended?, alignment: Alignment) {
        self.content = content
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        let frameChanged = previous?.width != width
            || previous?.height != height
            || previous?.alignment != alignment
        for control in node.elements?.values ?? [] {
            let control = control as! FixedFrameElement
            control.width = width
            control.height = height
            control.alignment = alignment
        }
        if frameChanged {
            node.root.application?.requestLayout()
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let fixedFrameElement = control.parent as? FixedFrameElement {
            fixedFrameElement.width = width
            fixedFrameElement.height = height
            fixedFrameElement.alignment = alignment
            return fixedFrameElement
        }
        let fixedFrameElement = FixedFrameElement(width: width, height: height, alignment: alignment)
        fixedFrameElement.addSubview(control, at: 0)
        node.elements?.add(fixedFrameElement)
        return fixedFrameElement
    }

    private class FixedFrameElement: Element {
        override var donatesDescendantPointerOnClick: Bool { true }
        var width: Extended?
        var height: Extended?
        var alignment: Alignment

        init(width: Extended?, height: Extended?, alignment: Alignment) {
            self.width = width
            self.height = height
            self.alignment = alignment
        }

        override func size(proposedSize: Size) -> Size {
            var proposedSize = proposedSize
            proposedSize.width = width ?? proposedSize.width
            proposedSize.height = height ?? proposedSize.height
            var size = children[0].size(proposedSize: proposedSize)
            size.width = width ?? size.width
            size.height = height ?? size.height
            return size
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: children[0].size(proposedSize: size))
            let oldFrame = children[0].layer.frame
            let child = children[0].layer.frame.size
            children[0].layer.frame.position.line = Self.alignedOffset(
                container: size.height,
                child: child.height,
                vertical: alignment.verticalAlignment
            )
            children[0].layer.frame.position.column = Self.alignedOffset(
                container: size.width,
                child: child.width,
                horizontal: alignment.horizontalAlignment
            )
            if oldFrame != children[0].layer.frame {
                self.layer.invalidate(rect: oldFrame)
                self.layer.invalidate(rect: children[0].layer.frame)
            }
        }

        private static func alignedOffset(
            container: Extended,
            child: Extended,
            vertical: VerticalAlignment
        ) -> Extended {
            switch vertical {
            case .top: return 0
            case .bottom:
                guard container != .infinity, child != .infinity else { return 0 }
                return container - child
            case .center:
                guard container != .infinity, child != .infinity else { return 0 }
                return (container - child) / 2
            }
        }

        private static func alignedOffset(
            container: Extended,
            child: Extended,
            horizontal: HorizontalAlignment
        ) -> Extended {
            switch horizontal {
            case .leading: return 0
            case .trailing:
                guard container != .infinity, child != .infinity else { return 0 }
                return container - child
            case .center:
                guard container != .infinity, child != .infinity else { return 0 }
                return (container - child) / 2
            }
        }
    }
}
