import Foundation

public extension View {
    /// Aligns content to the top leading corner by default. Use the `.infinity` value for
    /// `maxWidth` or `maxHeight` to allow views to take up all space.
    func frame(
        minWidth: Extended? = nil,
        maxWidth: Extended? = nil,
        minHeight: Extended? = nil,
        maxHeight: Extended? = nil,
        alignment: Alignment = .center
    ) -> some View {
        FlexibleFrame(content: self, minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight, alignment: alignment)
    }
}

private struct FlexibleFrame<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let minWidth: Extended?
    let maxWidth: Extended?
    let minHeight: Extended?
    let maxHeight: Extended?
    let alignment: Alignment
    
    static var size: Int? { Content.size }
    
    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }
    
    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        let frameChanged = previous?.minWidth != minWidth
            || previous?.maxWidth != maxWidth
            || previous?.minHeight != minHeight
            || previous?.maxHeight != maxHeight
            || previous?.alignment != alignment
        for control in node.elements?.values ?? [] {
            let control = control as! FlexibleFrameElement
            control.minWidth = minWidth
            control.maxWidth = maxWidth
            control.minHeight = minHeight
            control.maxHeight = maxHeight
            control.alignment = alignment
        }
        if frameChanged {
            node.root.application?.requestLayout()
        }
    }
    
    func passElement(_ control: Element, node: Node) -> Element {
        if let frame = control.parent as? FlexibleFrameElement {
            frame.minWidth = minWidth
            frame.maxWidth = maxWidth
            frame.minHeight = minHeight
            frame.maxHeight = maxHeight
            frame.alignment = alignment
            return frame
        }
        let frame = FlexibleFrameElement(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight, alignment: alignment)
        frame.addSubview(control, at: 0)
        node.elements?.add(frame)
        return frame
    }
    
    private class FlexibleFrameElement: Element {
        var minWidth: Extended?
        var maxWidth: Extended?
        var minHeight: Extended?
        var maxHeight: Extended?
        var alignment: Alignment
        
        init(minWidth: Extended?, maxWidth: Extended?, minHeight: Extended?, maxHeight: Extended?, alignment: Alignment) {
            self.minWidth = minWidth
            self.maxWidth = maxWidth
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.alignment = alignment
        }
        
        override func size(proposedSize: Size) -> Size {
            // Expand to the offered size when maxWidth/maxHeight is set (incl. `.infinity`).
            // Do NOT collapse an unbounded offer to the child's ideal size — that breaks
            // HStack/VStack flexibility (`.frame(maxWidth: .infinity)` must stay expandable).
            var proposedSize = proposedSize
            proposedSize.width = min(maxWidth ?? .infinity, max(minWidth ?? 0, proposedSize.width))
            proposedSize.height = min(maxHeight ?? .infinity, max(minHeight ?? 0, proposedSize.height))
            let size = children[0].size(proposedSize: proposedSize)
            if minHeight == nil, maxHeight == nil {
                proposedSize.height = size.height
            }
            if minWidth == nil, maxWidth == nil {
                proposedSize.width = size.width
            }
            return proposedSize
        }
        
        override func layout(size: Size) {
            super.layout(size: size)
            // 提案满尺寸，子视图可自行扩展（如 Spacer）；若仍更小则按 alignment 居中
            children[0].layout(size: children[0].size(proposedSize: size))
            let oldFrame = children[0].layer.frame
            let child = children[0].layer.frame.size
            children[0].layer.frame.position.line = alignedOffset(
                container: size.height,
                child: child.height,
                alignment: alignment.verticalAlignment
            )
            children[0].layer.frame.position.column = alignedOffset(
                container: size.width,
                child: child.width,
                alignment: alignment.horizontalAlignment
            )
            if oldFrame != children[0].layer.frame {
                self.layer.invalidate(rect: oldFrame)
                self.layer.invalidate(rect: children[0].layer.frame)
            }
        }

        /// Avoid ∞−∞ when `.fixedSize()` proposes infinity into `.frame(maxWidth: .infinity)`.
        private func alignedOffset(
            container: Extended,
            child: Extended,
            alignment: VerticalAlignment
        ) -> Extended {
            switch alignment {
            case .top: return 0
            case .bottom:
                guard container != .infinity, child != .infinity else { return 0 }
                return container - child
            case .center:
                guard container != .infinity, child != .infinity else { return 0 }
                return (container - child) / 2
            }
        }

        private func alignedOffset(
            container: Extended,
            child: Extended,
            alignment: HorizontalAlignment
        ) -> Extended {
            switch alignment {
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
