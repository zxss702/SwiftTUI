import Foundation

@MainActor public struct VStack<Content: View>: View, PrimitiveView, LayoutRootView {
    public let content: Content
    let alignment: HorizontalAlignment
    let spacing: Extended?

    /// Horizontally aligns content to the leading edge by default.
    public init(alignment: HorizontalAlignment = .leading, spacing: Extended? = nil, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
        self.spacing = spacing
    }
    
    init(content: Content, alignment: HorizontalAlignment = .leading, spacing: Extended? = nil) {
        self.content = content
        self.alignment = alignment
        self.spacing = spacing
    }
    
    static var size: Int? { 1 }
    
    func loadData(node: Node) {
        for i in 0 ..< node.children[0].size {
            (node.element as! VStackElement).addSubview(node.children[0].element(at: i), at: i)
        }
    }
    
    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.element = VStackElement(alignment: alignment, spacing: spacing ?? 0)
        node.environment = { $0.stackOrientation = .vertical }
    }
    
    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! VStackElement
        let newSpacing = spacing ?? 0
        if previous?.alignment != alignment || control.spacing != newSpacing {
            node.root.application?.requestLayout()
        }
        control.alignment = alignment
        control.spacing = newSpacing
        control.reconcileChildren(from: node.children[0])
    }
    
    func insertElement(at index: Int, node: Node) {
        // 以 `reconcileChildren` 为准（同 HStack：避免 Optional + 惰性 ForEach 错位越界）。
    }
    
    func removeElement(at index: Int, node: Node) {
        // 见 insertElement。
    }
    
    private class VStackElement: Element {
        var alignment: HorizontalAlignment
        var spacing: Extended

        override var donatesDescendantPointerOnClick: Bool { true }

        init(alignment: HorizontalAlignment, spacing: Extended) {
            self.alignment = alignment
            self.spacing = spacing
        }
        
        // MARK: - Layout
        
        override func size(proposedSize: Size) -> Size {
            var size: Size = .zero
            var remainingItems = children.count
            for control in children.sorted(by: Self.layoutOrder(width: proposedSize.width)) {
                let remainingHeight = size.height == .infinity ? .infinity : (proposedSize.height - size.height)
                let childSize = control.sizeCached(proposedSize: Size(width: proposedSize.width, height: remainingHeight / Extended(remainingItems)))
                size.height += childSize.height
                if remainingItems > 1 {
                    size.height += spacing
                }
                size.width = max(size.width, childSize.width)
                remainingItems -= 1
            }
            return size
        }
        
        override func layout(size: Size) {
            super.layout(size: size)
            var remainingItems = children.count
            var remainingHeight = size.height
            for control in children.sorted(by: Self.layoutOrder(width: size.width)) {
                let childSize = control.sizeCached(proposedSize: Size(width: size.width, height: remainingHeight / Extended(remainingItems)))
                control.layout(size: childSize)
                if remainingItems > 1 {
                    remainingHeight -= spacing
                }
                remainingItems -= 1
                if remainingHeight != .infinity {
                    remainingHeight -= childSize.height
                } else if childSize.height == .infinity {
                    // 多个无界子视图：后续按 0 剩余处理，避免 ∞-∞
                    remainingHeight = 0
                }
            }
            var line: Extended = 0
            for control in children {
                let oldFrame = control.layer.frame
                control.layer.frame.position.line = line
                line += control.layer.frame.size.height
                line += spacing
                switch alignment {
                case .leading: control.layer.frame.position.column = 0
                case .center: control.layer.frame.position.column = (size.width - control.layer.frame.size.width) / 2
                case .trailing: control.layer.frame.position.column = size.width - control.layer.frame.size.width
                }
                if oldFrame != control.layer.frame {
                    self.layer.invalidate(rect: oldFrame)
                    self.layer.invalidate(rect: control.layer.frame)
                }
            }
        }

        private static func layoutOrder(width: Extended) -> (Element, Element) -> Bool {
            { a, b in
                if a.layoutPriority != b.layoutPriority {
                    return a.layoutPriority > b.layoutPriority
                }
                return a.verticalFlexibility(width: width) < b.verticalFlexibility(width: width)
            }
        }
    }
}
