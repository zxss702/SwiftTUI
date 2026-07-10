import Foundation

// MARK: - Edge（popover 公开参数；布局自动选边时可忽略）

public enum Edge: Sendable {
    case top
    case bottom
    case leading
    case trailing
}

// MARK: - UnitPoint stub（popover 签名对齐；TUI 固定 bounds 锚点）

public struct UnitPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
}

// MARK: - sheet

public extension View {
    func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        PresentationBindingModifier(
            kind: .sheet,
            isPresented: isPresented,
            onDismiss: onDismiss,
            presented: content,
            content: self
        )
    }

    func sheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        PresentationItemModifier(
            kind: .sheet,
            item: item,
            onDismiss: onDismiss,
            presented: content,
            content: self
        )
    }
}

// MARK: - popover

public extension View {
    func popover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: UnitPoint = .center,
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        _ = attachmentAnchor
        _ = arrowEdge
        return PopoverBindingModifier(
            isPresented: isPresented,
            presented: content,
            content: self
        )
    }

    func popover<Item: Identifiable, PopoverContent: View>(
        item: Binding<Item?>,
        attachmentAnchor: UnitPoint = .center,
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping (Item) -> PopoverContent
    ) -> some View {
        _ = attachmentAnchor
        _ = arrowEdge
        return PopoverItemModifier(
            item: item,
            presented: content,
            content: self
        )
    }
}
