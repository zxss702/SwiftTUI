import Foundation

// MARK: - View.id

@MainActor
final class IdentityAnchorControl: Control {
    var id: AnyHashable

    init(id: AnyHashable) {
        self.id = id
    }

    override func size(proposedSize: Size) -> Size {
        children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children[0].layout(size: size)
    }
}

@MainActor
private struct IdentityAnchor<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let id: AnyHashable

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            (control as! IdentityAnchorControl).id = id
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? IdentityAnchorControl {
            existing.id = id
            return existing
        }
        let wrapper = IdentityAnchorControl(id: id)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }
}

public extension View {
    func id<ID: Hashable>(_ id: ID) -> some View {
        IdentityAnchor(content: self, id: AnyHashable(id))
    }
}

// MARK: - ScrollViewReader

@MainActor
public final class ScrollViewProxy {
    weak var bridge: ScrollToIdentityBridging?

    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        _ = anchor
        bridge?.scrollToIdentity(AnyHashable(id))
    }
}

@MainActor
protocol ScrollToIdentityBridging: AnyObject {
    func scrollToIdentity(_ id: AnyHashable)
}

@MainActor
public struct ScrollViewReader<Content: View>: View {
    let content: (ScrollViewProxy) -> Content

    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        ScrollViewReaderHost(content: content)
    }
}

@MainActor
private struct ScrollViewReaderHost<Content: View>: View, PrimitiveView {
    let content: (ScrollViewProxy) -> Content

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        let proxy = ScrollViewProxy()
        node.state["proxy"] = proxy
        node.addNode(at: 0, Node(view: content(proxy).view))
        let control = ScrollViewReaderControl()
        control.proxy = proxy
        proxy.bridge = control
        control.contentControl = node.children[0].control(at: 0)
        control.addSubview(control.contentControl, at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        let proxy = (node.state["proxy"] as? ScrollViewProxy) ?? ScrollViewProxy()
        node.state["proxy"] = proxy
        node.children[0].update(using: content(proxy).view)
        let control = node.control as! ScrollViewReaderControl
        control.proxy = proxy
        proxy.bridge = control
        control.contentControl = node.children[0].control(at: 0)
    }
}

@MainActor
private final class ScrollViewReaderControl: Control, ScrollToIdentityBridging {
    var proxy: ScrollViewProxy!
    var contentControl: Control!

    override func size(proposedSize: Size) -> Size {
        contentControl.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentControl.layout(size: size)
    }

    func scrollToIdentity(_ id: AnyHashable) {
        guard let target = findIdentity(id, in: contentControl) else { return }
        if let scroll = findScrollAncestor(of: target) {
            scroll.scrollToIdentity(id)
        } else {
            // 无 ScrollView：尽量把目标滚进可见区
            target.scroll(to: .zero)
        }
    }

    private func findIdentity(_ id: AnyHashable, in control: Control) -> IdentityAnchorControl? {
        if let anchor = control as? IdentityAnchorControl, anchor.id == id {
            return anchor
        }
        for child in control.children {
            if let found = findIdentity(id, in: child) { return found }
        }
        return nil
    }

    private func findScrollAncestor(of control: Control) -> ScrollToIdentityBridging? {
        var current: Control? = control
        while let c = current {
            if let scroll = c as? ScrollToIdentityBridging, !(scroll is ScrollViewReaderControl) {
                return scroll
            }
            current = c.parent
        }
        // 也在子树里找 ScrollView（reader 包在外面时）
        return findScrollDescendant(in: contentControl)
    }

    private func findScrollDescendant(in control: Control) -> ScrollToIdentityBridging? {
        if let scroll = control as? ScrollToIdentityBridging, !(scroll is ScrollViewReaderControl) {
            return scroll
        }
        for child in control.children {
            if let found = findScrollDescendant(in: child) { return found }
        }
        return nil
    }
}
