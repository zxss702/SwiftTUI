import Foundation

// MARK: - View.id

@MainActor
final class IdentityAnchorElement: Element {
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
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! IdentityAnchorElement).id = id
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? IdentityAnchorElement {
            existing.id = id
            return existing
        }
        let wrapper = IdentityAnchorElement(id: id)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
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
        bridge?.scrollToIdentity(AnyHashable(id), anchor: anchor)
    }
}

@MainActor
protocol ScrollToIdentityBridging: AnyObject {
    func scrollToIdentity(_ id: AnyHashable, anchor: UnitPoint?)
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
        node.storage["proxy"] = proxy
        node.addNode(at: 0, Node(view: content(proxy).view))
        let control = ScrollViewReaderElement()
        control.proxy = proxy
        proxy.bridge = control
        control.contentElement = node.children[0].element(at: 0)
        control.addSubview(control.contentElement, at: 0)
        node.element = control
        // 内容构建过程中触发的（如 onChange initial）滚动此时 contentElement 尚未就绪，
        // 会被暂存为 pending，构建完成后在此统一执行。
        control.flushPendingScroll()
    }

    func updateNode(_ node: Node) {
        node.view = self
        let proxy = (node.storage["proxy"] as? ScrollViewProxy) ?? ScrollViewProxy()
        node.storage["proxy"] = proxy
        node.children[0].update(using: content(proxy).view)
        let control = node.element as! ScrollViewReaderElement
        control.proxy = proxy
        proxy.bridge = control
        let newContent = node.children[0].element(at: 0)
        control.contentElement = newContent
        control.syncChild(newContent)
        control.flushPendingScroll()
    }
}

@MainActor
private final class ScrollViewReaderElement: Element, ScrollToIdentityBridging {
    var proxy: ScrollViewProxy!
    var contentElement: Element!

    /// 内容尚未构建完成时收到的滚动请求，稍后 `flushPendingScroll()` 补执行。
    private var pendingScroll: (id: AnyHashable, anchor: UnitPoint?)?

    override func size(proposedSize: Size) -> Size {
        contentElement.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentElement.layout(size: size)
    }

    func scrollToIdentity(_ id: AnyHashable, anchor: UnitPoint?) {
        // 内容元素还未就绪（例如 onChange initial 在内容构建期间触发）：暂存，稍后补执行。
        guard let contentElement else {
            pendingScroll = (id, anchor)
            return
        }
        // Prefer a ScrollView that actually contains the target when it is
        // already materialized.
        if let target = findIdentity(id, in: contentElement),
           let scroll = findScrollAncestor(of: target)
        {
            scroll.scrollToIdentity(id, anchor: anchor)
            return
        }
        // Lazy / not yet loaded: find the enclosing ScrollView under this reader
        // and let it resolve via estimated offsets.
        if let scroll = findScrollDescendant(in: contentElement) {
            scroll.scrollToIdentity(id, anchor: anchor)
        }
    }

    func flushPendingScroll() {
        guard contentElement != nil, let pending = pendingScroll else { return }
        pendingScroll = nil
        scrollToIdentity(pending.id, anchor: pending.anchor)
    }

    private func findIdentity(_ id: AnyHashable, in control: Element) -> IdentityAnchorElement? {
        if let anchor = control as? IdentityAnchorElement, anchor.id == id {
            return anchor
        }
        for child in control.children {
            if let found = findIdentity(id, in: child) { return found }
        }
        return nil
    }

    private func findScrollAncestor(of control: Element) -> ScrollToIdentityBridging? {
        var current: Element? = control
        while let c = current {
            if let scroll = c as? ScrollToIdentityBridging, !(scroll is ScrollViewReaderElement) {
                return scroll
            }
            current = c.parent
        }
        return nil
    }

    private func findScrollDescendant(in control: Element) -> ScrollToIdentityBridging? {
        if let scroll = control as? ScrollToIdentityBridging, !(scroll is ScrollViewReaderElement) {
            return scroll
        }
        for child in control.children {
            if let found = findScrollDescendant(in: child) { return found }
        }
        return nil
    }
}

// MARK: - Shared identity helpers

@MainActor
enum ScrollIdentityLookup {
    static func findIdentity(_ id: AnyHashable, in control: Element) -> IdentityAnchorElement? {
        if let anchor = control as? IdentityAnchorElement, anchor.id == id {
            return anchor
        }
        for child in control.children {
            if let found = findIdentity(id, in: child) { return found }
        }
        return nil
    }

    static func lazyContentOffset(for id: AnyHashable, in control: Element) -> Extended? {
        if let lazy = control as? LazyIdentityOffsetProviding,
           let offset = lazy.contentLineOffset(forIdentity: id)
        {
            return offset
        }
        for child in control.children {
            if let offset = lazyContentOffset(for: id, in: child) {
                return offset
            }
        }
        return nil
    }
}
