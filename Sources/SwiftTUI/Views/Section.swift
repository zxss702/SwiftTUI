import Foundation

// MARK: - Section chrome (header / footer markers for LazyVGrid)

enum SectionChromeRole {
    case header
    case footer
}

/// Wraps a section header or footer control so LazyVGrid can treat it as full-width chrome.
@MainActor
final class SectionChromeElement: Element {
    var role: SectionChromeRole

    init(role: SectionChromeRole) {
        self.role = role
    }

    override func size(proposedSize: Size) -> Size {
        guard !children.isEmpty else { return Size(width: 0, height: 0) }
        return children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        guard !children.isEmpty else { return }
        children[0].layout(size: size)
    }
}

/// Marker protocol so LazyVGrid can discover `Section` nodes without materializing every control.
@MainActor
protocol SectionLayoutView: GenericView {}

@MainActor
private struct SectionChrome<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let role: SectionChromeRole

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! SectionChromeElement).role = role
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? SectionChromeElement {
            existing.role = role
            return existing
        }
        let wrapper = SectionChromeElement(role: role)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }
}

// MARK: - Section

/// Aligns SwiftUI.`Section<Parent, Content, Footer>`: flattens into the parent control list
/// (like `Group`), with header/footer marked for lazy containers that support pinning.
@MainActor
public struct Section<Parent: View, Content: View, Footer: View>: View, PrimitiveView, SectionLayoutView {
    public let content: Content
    public let header: Parent
    public let footer: Footer

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    static var size: Int? {
        if let h = Parent.size, let c = Content.size, let f = Footer.size {
            return h + c + f
        }
        return nil
    }

    func buildNode(_ node: Node) {
        // Order: header → content → footer (flat indices for LazyVGrid band planning)
        node.addNode(at: 0, Node(view: SectionChrome(content: header, role: .header).view))
        node.addNode(at: 1, Node(view: content.view))
        node.addNode(at: 2, Node(view: SectionChrome(content: footer, role: .footer).view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: SectionChrome(content: header, role: .header).view)
        node.children[1].update(using: content.view)
        node.children[2].update(using: SectionChrome(content: footer, role: .footer).view)
    }
}

extension Section where Parent == EmptyView {
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension Section where Footer == EmptyView {
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent
    ) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension Section where Parent == Text, Footer == EmptyView {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(String(title)) }, footer: { EmptyView() })
    }
}
