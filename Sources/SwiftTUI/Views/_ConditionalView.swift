import Foundation

@MainActor public struct _ConditionalView<TrueContent: View, FalseContent: View>: View, PrimitiveView {
    enum ConditionalContent {
        case a(TrueContent)
        case b(FalseContent)
    }

    let content: ConditionalContent

    static var size: Int? {
        if TrueContent.size == FalseContent.size { return TrueContent.size }
        return nil
    }

    func buildNode(_ node: Node) {
        switch content {
        case .a(let value):
            node.addNode(at: 0, Node(view: value.view))
        case .b(let value):
            node.addNode(at: 0, Node(view: value.view))
        }
    }

    func updateNode(_ node: Node) {
        let last = node.view as! Self
        node.view = self
        switch (last.content, self.content) {
        case (.a, .a(let newValue)):
            node.children[0].update(using: newValue.view)
        case (.b, .b(let newValue)):
            node.children[0].update(using: newValue.view)
        case (.b, .a(let newValue)):
            // Branch identity swap (e.g. `if hover { Menu }`). Suppress hover
            // resign so `onHover` is not spuriously cleared mid-swap.
            withHoverResignSuppressed(on: node) {
                node.removeNode(at: 0)
                node.addNode(at: 0, Node(view: newValue.view))
            }
        case (.a, .b(let newValue)):
            withHoverResignSuppressed(on: node) {
                node.removeNode(at: 0)
                node.addNode(at: 0, Node(view: newValue.view))
            }
        }
    }

    private func withHoverResignSuppressed(on node: Node, _ body: () -> Void) {
        let window = node.root.application?.window
        let previousSuppress = window?.suppressHoverResign ?? false
        window?.suppressHoverResign = true
        defer { window?.suppressHoverResign = previousSuppress }
        body()
    }
}
