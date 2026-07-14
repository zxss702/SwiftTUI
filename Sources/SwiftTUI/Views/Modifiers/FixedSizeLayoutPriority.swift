import Foundation

public extension View {
    /// 沿指定轴使用理想尺寸（不受父视图拉伸）。
    func fixedSize(horizontal: Bool = true, vertical: Bool = true) -> some View {
        FixedSizeModifier(content: self, horizontal: horizontal, vertical: vertical)
    }

    /// 布局优先级；同栈内更高优先级的子视图优先获得空间。
    func layoutPriority(_ value: Double) -> some View {
        LayoutPriorityModifier(content: self, priority: value)
    }
}

// MARK: - fixedSize

@MainActor
private struct FixedSizeModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let horizontal: Bool
    let vertical: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! FixedSizeElement
            control.horizontal = horizontal
            control.vertical = vertical
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? FixedSizeElement {
            existing.horizontal = horizontal
            existing.vertical = vertical
            return existing
        }
        let wrapper = FixedSizeElement(horizontal: horizontal, vertical: vertical)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class FixedSizeElement: Element {
        var horizontal: Bool
        var vertical: Bool

        init(horizontal: Bool, vertical: Bool) {
            self.horizontal = horizontal
            self.vertical = vertical
        }

        override func size(proposedSize: Size) -> Size {
            let proposed = Size(
                width: horizontal ? .infinity : proposedSize.width,
                height: vertical ? .infinity : proposedSize.height
            )
            let child = children[0].size(proposedSize: proposed)
            // Ideal size must be finite on fixed axes. Expanding children
            // (e.g. `.frame(maxWidth: .infinity)`) may report ∞ under an ∞ offer —
            // fall back to the parent's proposal (or 0) so stacks stay stable.
            let width: Extended
            if horizontal {
                width = child.width == .infinity
                    ? (proposedSize.width == .infinity ? 0 : proposedSize.width)
                    : child.width
            } else {
                width = child.width
            }
            let height: Extended
            if vertical {
                height = child.height == .infinity
                    ? (proposedSize.height == .infinity ? 0 : proposedSize.height)
                    : child.height
            } else {
                height = child.height
            }
            return Size(width: width, height: height)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            var childSize = children[0].size(proposedSize: Size(
                width: horizontal ? .infinity : size.width,
                height: vertical ? .infinity : size.height
            ))
            if horizontal, childSize.width == .infinity { childSize.width = size.width }
            if vertical, childSize.height == .infinity { childSize.height = size.height }
            children[0].layout(size: childSize)
        }

        override func horizontalFlexibility(height: Extended) -> Extended {
            horizontal ? 0 : super.horizontalFlexibility(height: height)
        }

        override func verticalFlexibility(width: Extended) -> Extended {
            vertical ? 0 : super.verticalFlexibility(width: width)
        }
    }
}

// MARK: - layoutPriority

@MainActor
private struct LayoutPriorityModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let priority: Double

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        let previous = node.view as? Self
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            (control as! LayoutPriorityElement).priority = priority
        }
        if previous?.priority != priority {
            node.root.application?.requestLayout()
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? LayoutPriorityElement {
            existing.priority = priority
            return existing
        }
        let wrapper = LayoutPriorityElement(priority: priority)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class LayoutPriorityElement: Element {
        var priority: Double

        init(priority: Double) {
            self.priority = priority
        }

        override var layoutPriority: Double { priority }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }
    }
}
