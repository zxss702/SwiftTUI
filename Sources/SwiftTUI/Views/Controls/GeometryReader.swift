import Foundation

@MainActor public struct GeometryReader<Content: View>: View, PrimitiveView {
    let content: (Size) -> Content

    public init(@ViewBuilder content: @escaping (Size) -> Content) {
        self.content = content
    }

    @State private var geometry: Size = Size(width: 1, height: 1)

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupStateProperties(node: node)
        let childView = node.observing { VStack(content: content(geometry)).view }
        node.addNode(at: 0, Node(view: childView))
        let control = GeometryReaderElement(geometry: _geometry)
        control.node = node
        control.rebuildChild = { [content] size in
            // Called from layout — still must register Observable deps on this node.
            node.observing { VStack(content: content(size)).view }
        }
        node.element = control
        control.addSubview(node.children[0].element(at: 0), at: 0)
    }

    func updateNode(_ node: Node) {
        setupStateProperties(node: node)
        node.view = self
        let control = node.element as! GeometryReaderElement
        control.node = node
        control.rebuildChild = { [content] size in
            node.observing { VStack(content: content(size)).view }
        }
        let childView = node.observing { VStack(content: content(geometry)).view }
        node.children[0].update(using: childView)
        control.syncChildElement()
    }

    private class GeometryReaderElement: Element {
        let geometry: State<Size>
        weak var node: Node?
        var rebuildChild: ((Size) -> GenericView)?

        init(geometry: State<Size>) {
            self.geometry = geometry
        }

        /// Publish finite proposed axes during measure so children see the real
        /// stack/viewport width (not the `@State` placeholder `1`).
        ///
        /// When an axis is `.infinity` (typical inside vertical `ScrollView` /
        /// `LazyVStack`), report the child's measured size on that axis so rows
        /// are not clipped to a single line / infinite height.
        override func size(proposedSize: Size) -> Size {
            publishFiniteAxes(from: proposedSize)
            let childProposal = Size(
                width: proposedSize.width == .infinity
                    ? geometry.wrappedValue.width
                    : proposedSize.width,
                height: proposedSize.height == .infinity
                    ? .infinity
                    : proposedSize.height
            )
            let childSize = children.isEmpty
                ? Size.zero
                : children[0].size(proposedSize: childProposal)
            return Size(
                width: proposedSize.width == .infinity ? childSize.width : proposedSize.width,
                height: proposedSize.height == .infinity ? childSize.height : proposedSize.height
            )
        }

        override func layout(size: Size) {
            super.layout(size: size)
            // Never publish ∞ / 0 probes — only real finite sizes refresh content.
            var published = geometry.wrappedValue
            if size.width != .infinity, size.width > 0 {
                published.width = size.width
            }
            if size.height != .infinity, size.height > 0 {
                published.height = size.height
            }
            if geometry.wrappedValue != published {
                geometry.setValue(published, invalidate: false)
                rebuildContent(with: published)
            }
            if !children.isEmpty {
                let childLayoutSize = Size(
                    width: size.width == .infinity ? published.width : max(size.width, published.width),
                    height: size.height == .infinity
                        ? children[0].size(proposedSize: Size(width: published.width, height: .infinity)).height
                        : (size.height > 0 ? size.height : published.height)
                )
                children[0].layout(size: childLayoutSize)
            }
        }

        /// Copy finite proposed axes into `@State` and rebuild content before
        /// measure continues. Critical inside ScrollView / LazyVStack: the first
        /// `size(proposed:)` already knows the stack width, but body would
        /// otherwise still close over the placeholder `width: 1`.
        ///
        /// Size unchanged → no rebuild. Skip 0 / negative probes (HStack min
        /// flexibility) so they never trash geometry or rebuild the subtree.
        private func publishFiniteAxes(from proposed: Size) {
            var next = geometry.wrappedValue
            var changed = false
            if proposed.width != .infinity, proposed.width > 0, next.width != proposed.width {
                next.width = proposed.width
                changed = true
            }
            if proposed.height != .infinity, proposed.height > 0, next.height != proposed.height {
                next.height = proposed.height
                changed = true
            }
            guard changed else { return }
            geometry.setValue(next, invalidate: false)
            rebuildContent(with: next)
        }

        /// Rebuild only when the published size actually changed.
        private func rebuildContent(with size: Size) {
            guard let node, let rebuildChild, !node.children.isEmpty else { return }
            node.children[0].update(using: rebuildChild(size))
            syncChildElement()
        }

        func syncChildElement() {
            guard let node, !node.children.isEmpty else { return }
            syncChild(node.children[0].element(at: 0))
        }
    }
}
