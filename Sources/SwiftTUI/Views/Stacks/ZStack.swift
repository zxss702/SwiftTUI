import Foundation

@MainActor public struct ZStack<Content: View>: View, PrimitiveView, LayoutRootView {
    public let content: Content
    let alignment: Alignment
    
    // Aligns content to the top leading corner by default.
    public init(alignment: Alignment = .topLeading, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }
    
    init(content: Content, alignment: Alignment = .center) {
        self.content = content
        self.alignment = alignment
    }
    
    static var size: Int? { 1 }
    
    func loadData(node: Node) {
        for i in 0 ..< node.children[0].size {
            (node.element as! ZStackElement).addSubview(node.children[0].element(at: i), at: i)
        }
    }
    
    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.element = ZStackElement(alignment: alignment)
    }
    
    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! ZStackElement
        if previous?.alignment != alignment {
            node.root.application?.requestLayout()
        }
        control.alignment = alignment
        control.reconcileChildren(from: node.children[0])
    }
    
    func insertElement(at index: Int, node: Node) {
        // 以 `reconcileChildren` 为准（同 HStack：避免 Optional + 惰性 ForEach 错位越界）。
    }
    
    func removeElement(at index: Int, node: Node) {
        // 见 insertElement。
    }
    
    private class ZStackElement: Element {
        var alignment: Alignment
        
        init(alignment: Alignment) {
            self.alignment = alignment
        }
        
        // MARK: - Layout
        override func size(proposedSize: Size) -> Size {
            var size: Size = .zero
            for control in children {
                let childSize = control.sizeCached(proposedSize: Size(width: proposedSize.width, height: proposedSize.height))
                size.height = max(size.height, childSize.height)
                size.width = max(size.width, childSize.width)
            }
            return size
        }
        
        override func layout(size: Size) {
            super.layout(size: size)
            for control in children {
                let childSize = control.sizeCached(proposedSize: Size(width: size.width, height: size.height))
                control.layout(size: childSize)
            }
            for control in children {
                let child = control.layer.frame.size
                control.layer.frame.position.column = Self.alignedOffset(
                    container: size.width,
                    child: child.width,
                    horizontal: alignment.horizontalAlignment
                )
                control.layer.frame.position.line = Self.alignedOffset(
                    container: size.height,
                    child: child.height,
                    vertical: alignment.verticalAlignment
                )
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
    }
}
