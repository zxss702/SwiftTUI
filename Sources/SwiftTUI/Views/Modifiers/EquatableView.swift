import Foundation

public extension View where Self: Equatable {
    /// 内容等值时跳过子树 update（对齐 SwiftUI `equatable()`）。
    ///
    /// `Equatable` 必须覆盖所有会影响 Element 绘制/布局/交互的字段；
    /// 漏掉的字段在 `==` 为 true 时不会推到 Element 树，表现为 stale UI。
    func equatable() -> some View {
        EquatableView(content: self)
    }
}

@MainActor
private struct EquatableView<Content: View & Equatable>: View, PrimitiveView {
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        if let previous, previous.content == content {
            return
        }
        node.children[0].update(using: content.view)
    }
}
