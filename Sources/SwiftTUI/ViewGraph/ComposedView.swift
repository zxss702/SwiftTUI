import Foundation

/// This wraps a composed (user-defined) view, so that it can be used in a view graph node.
@MainActor struct ComposedView<I: View>: GenericView {
    let view: I

    func buildNode(_ node: Node) {
        view.setupStateProperties(node: node)
        view.setupEnvironmentProperties(node: node)
        // Track only `body` reads for this node. Child `update`/`build` must stay
        // outside — nested `withObservationTracking` would attribute child
        // `@Observable` accesses to this parent as well.
        let bodyView = node.observing { view.body.view }
        node.addNode(at: 0, Node(view: bodyView))
    }

    func updateNode(_ node: Node) {
        view.setupStateProperties(node: node)
        view.setupEnvironmentProperties(node: node)
        node.view = self
        let bodyView = node.observing { view.body.view }
        node.children[0].update(using: bodyView)
    }

    static var size: Int? {
        I.Body.size
    }
}
