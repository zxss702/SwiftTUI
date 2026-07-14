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
        node.addNode(at: 0, Node(view: VStack(content: content(geometry))))
        let control = GeometryReaderElement(geometry: _geometry)
        control.node = node
        control.rebuildChild = { [content] size in
            VStack(content: content(size)).view
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
            VStack(content: content(size)).view
        }
        node.children[0].update(using: VStack(content: content(geometry)))
        control.syncChildElement()
    }

    private class GeometryReaderElement: Element {
        let geometry: State<Size>
        weak var node: Node?
        var rebuildChild: ((Size) -> GenericView)?

        init(geometry: State<Size>) {
            self.geometry = geometry
        }

        override func size(proposedSize: Size) -> Size {
            return proposedSize
        }

        override func layout(size: Size) {
            super.layout(size: size)
            // Publish size and sync-update the child tree *before* laying out children,
            // so size-driven `if` branches switch in the same layout pass.
            if geometry.wrappedValue != size {
                geometry.setValue(size, invalidate: false)
                if let node, let rebuildChild, !node.children.isEmpty {
                    node.children[0].update(using: rebuildChild(size))
                    syncChildElement()
                }
            }
            if !children.isEmpty {
                children[0].layout(size: size)
            }
        }

        func syncChildElement() {
            guard let node, !node.children.isEmpty else { return }
            syncChild(node.children[0].element(at: 0))
        }
    }
}
