import Foundation

// MARK: - AnyView

/// 类型擦除的 View 容器，和 SwiftUI.AnyView 用法一致。
/// 内部使用 AnyViewStorage 来抹掉具体的 View 类型信息。
@MainActor public struct AnyView: View, PrimitiveView {
    let storage: AnyViewStorageBase

    public init<V: View>(_ view: V) {
        if let anyView = view as? AnyView {
            self.storage = anyView.storage
        } else {
            self.storage = AnyViewStorage(view: view)
        }
    }

    // size 为 nil 因为内部 View 类型在编译期不可知
    static var size: Int? { nil }

    func buildNode(_ node: Node) {
        storage.buildNode(node)
    }

    func updateNode(_ node: Node) {
        storage.updateNode(node)
    }
}

// MARK: - Storage Base

@MainActor class AnyViewStorageBase {
    func buildNode(_ node: Node) { fatalError("abstract") }
    func updateNode(_ node: Node) { fatalError("abstract") }
    var typeID: ObjectIdentifier { fatalError("abstract") }
}

// MARK: - Concrete Storage

@MainActor final class AnyViewStorage<V: View>: AnyViewStorageBase {
    let view: V

    init(view: V) {
        self.view = view
    }

    override var typeID: ObjectIdentifier {
        ObjectIdentifier(V.self)
    }

    override func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: view.view))
    }

    override func updateNode(_ node: Node) {
        let last = node.view as! AnyView
        node.view = AnyView(view)
        if last.storage.typeID == self.typeID {
            // 同类型，正常 diff 更新
            node.children[0].update(using: view.view)
        } else {
            // 类型不同，完全替换节点
            node.removeNode(at: 0)
            node.addNode(at: 0, Node(view: view.view))
        }
    }
}
