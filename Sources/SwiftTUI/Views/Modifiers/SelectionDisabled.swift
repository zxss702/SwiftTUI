import Foundation

public extension View {
    /// Excludes this view's screen area from any enclosing `.selectable()`
    /// region (SwiftUI-shaped): cells covered by it are never highlighted and
    /// never included in the copied text. Typical use: line-number gutters in
    /// a code diff, where dragging across rows should copy only the code.
    func selectionDisabled(_ disabled: Bool = true) -> some View {
        SelectionDisabledModifier(content: self, disabled: disabled)
    }
}

@MainActor
private struct SelectionDisabledModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let disabled: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for element in node.elements?.values ?? [] {
            (element as! SelectionMaskElement).isSelectionDisabled = disabled
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let mask = control.parent as? SelectionMaskElement {
            mask.isSelectionDisabled = disabled
            return mask
        }
        let mask = SelectionMaskElement(disabled: disabled)
        mask.addSubview(control, at: 0)
        node.elements?.add(mask)
        return mask
    }
}

/// Transparent container marking a subtree as excluded from text selection.
/// `SelectableElement` collects these frames into `SelectionHighlightRegion.maskedRects`.
@MainActor
final class SelectionMaskElement: Element {
    var isSelectionDisabled: Bool

    init(disabled: Bool) {
        self.isSelectionDisabled = disabled
    }

    override func size(proposedSize: Size) -> Size {
        children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children[0].layout(size: size)
    }
}
