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
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            let control = control as! FixedSizeControl
            control.horizontal = horizontal
            control.vertical = vertical
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? FixedSizeControl {
            existing.horizontal = horizontal
            existing.vertical = vertical
            return existing
        }
        let wrapper = FixedSizeControl(horizontal: horizontal, vertical: vertical)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }

    private final class FixedSizeControl: Control {
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
            return children[0].size(proposedSize: proposed)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            let childSize = children[0].size(proposedSize: Size(
                width: horizontal ? .infinity : size.width,
                height: vertical ? .infinity : size.height
            ))
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
        node.controls = WeakSet<Control>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.controls?.values ?? [] {
            (control as! LayoutPriorityControl).priority = priority
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        if let existing = control.parent as? LayoutPriorityControl {
            existing.priority = priority
            return existing
        }
        let wrapper = LayoutPriorityControl(priority: priority)
        wrapper.addSubview(control, at: 0)
        node.controls?.add(wrapper)
        return wrapper
    }

    private final class LayoutPriorityControl: Control {
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
