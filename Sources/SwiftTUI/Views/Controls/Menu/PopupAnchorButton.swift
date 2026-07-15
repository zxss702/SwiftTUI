import Foundation

// MARK: - Menu / Picker trigger (composed Button)

/// Menu/Picker 触发器：组合 `Button`，只额外带上锚点 `Rect` 与宿主 `Node`
///（给 `PopupPresenter` 继承 Environment）。不自建点击 Element。
@MainActor
struct PopupAnchorButton<Label: View>: View {
    let label: Label
    let action: (Rect, Node) -> Void

    var body: some View {
        PopupAnchorButtonHost(label: label, action: action)
    }
}

/// 薄宿主：子树是真正的 `Button`；本节点不设 `element`，由 `element(at:)` 透传。
@MainActor
private struct PopupAnchorButtonHost<Label: View>: View, PrimitiveView {
    let label: Label
    let action: (Rect, Node) -> Void

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: makeButton(hosting: node).view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: makeButton(hosting: node).view)
    }

    private func makeButton(hosting node: Node) -> some View {
        Button(
            action: { [weak node] in
                guard let node else { return }
                action(node.element(at: 0).absoluteFrame, node)
            },
            label: { label }
        )
    }
}
