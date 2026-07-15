import Foundation

@MainActor public struct HStack<Content: View>: View, PrimitiveView, LayoutRootView {
    public let content: Content
    let alignment: VerticalAlignment
    let spacing: Extended?

    /// Vertically aligns content to the top by default.
    public init(alignment: VerticalAlignment = .top, spacing: Extended? = nil, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
        self.spacing = spacing
    }

    static var size: Int? { 1 }

    func loadData(node: Node) {
        for i in 0 ..< node.children[0].size {
            (node.element as! HStackElement).addSubview(node.children[0].element(at: i), at: i)
        }
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.element = HStackElement(alignment: alignment, spacing: spacing ?? 1)
        node.environment = { $0.stackOrientation = .horizontal }
    }

    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! HStackElement
        let newSpacing = spacing ?? 1
        if previous?.alignment != alignment || control.spacing != newSpacing {
            node.root.application?.requestLayout()
        }
        control.alignment = alignment
        control.spacing = newSpacing
        control.reconcileChildren(from: node.children[0])
    }

    func insertElement(at index: Int, node: Node) {
        (node.element as! HStackElement).addSubview(node.children[0].element(at: index), at: index)
    }

    func removeElement(at index: Int, node: Node) {
        (node.element as! HStackElement).removeSubview(at: index)
    }

    private class HStackElement: Element {
        var alignment: VerticalAlignment
        var spacing: Extended

        override var donatesDescendantPointerOnClick: Bool { true }

        init(alignment: VerticalAlignment, spacing: Extended) {
            self.alignment = alignment
            self.spacing = spacing
        }

        // MARK: - Layout

        override func size(proposedSize: Size) -> Size {
            var size: Size = .zero
            var remainingItems = children.count
            for control in children.sorted(by: Self.layoutOrder(height: proposedSize.height)) {
                let remainingWidth = (size.width == .infinity) ? .infinity : (proposedSize.width - size.width)
                let childSize = control.sizeCached(proposedSize: Size(width: remainingWidth / Extended(remainingItems), height: proposedSize.height))
                size.width += childSize.width
                if remainingItems > 1 {
                    size.width += spacing
                }
                size.height = max(size.height, childSize.height)
                remainingItems -= 1
            }
            return size
        }

        override func layout(size: Size) {
            super.layout(size: size)
            var remainingItems = children.count
            var remainingWidth = size.width
            for control in children.sorted(by: Self.layoutOrder(height: size.height)) {
                let childSize = control.sizeCached(proposedSize: Size(width: remainingWidth / Extended(remainingItems), height: size.height))
                control.layout(size: childSize)
                if remainingItems > 1 {
                    remainingWidth -= spacing
                }
                remainingItems -= 1
                if remainingWidth != .infinity {
                    remainingWidth -= childSize.width
                } else if childSize.width == .infinity {
                    remainingWidth = 0
                }
            }
            var column: Extended = 0
            for control in children {
                let oldFrame = control.layer.frame
                control.layer.frame.position.column = column
                column += control.layer.frame.size.width
                column += spacing
                switch alignment {
                case .top: control.layer.frame.position.line = 0
                case .center: control.layer.frame.position.line = (size.height - control.layer.frame.size.height) / 2
                case .bottom: control.layer.frame.position.line = size.height - control.layer.frame.size.height
                }
                if oldFrame != control.layer.frame {
                    self.layer.invalidate(rect: oldFrame)
                    self.layer.invalidate(rect: control.layer.frame)
                }
            }
        }

        private static func layoutOrder(height: Extended) -> (Element, Element) -> Bool {
            { a, b in
                if a.layoutPriority != b.layoutPriority {
                    return a.layoutPriority > b.layoutPriority
                }
                return a.horizontalFlexibility(height: height) < b.horizontalFlexibility(height: height)
            }
        }
    }
}
