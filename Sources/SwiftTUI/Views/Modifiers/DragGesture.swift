import Foundation

// MARK: - DragGesture

/// 最小可用拖动手势：单元格坐标下的 `translation`。
@MainActor
public struct DragGesture {
    public struct Value: Equatable, Sendable {
        public var startLocation: Position
        public var location: Position
        public var translation: Size

        public init(startLocation: Position, location: Position, translation: Size) {
            self.startLocation = startLocation
            self.location = location
            self.translation = translation
        }
    }

    private var minimumDistance: Int
    private var onChanged: ((Value) -> Void)?
    private var onEnded: ((Value) -> Void)?

    public init(minimumDistance: Int = 1) {
        self.minimumDistance = max(0, minimumDistance)
    }

    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onChanged = action
        return copy
    }

    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onEnded = action
        return copy
    }

    fileprivate var _minimumDistance: Int { minimumDistance }
    fileprivate var _onChanged: ((Value) -> Void)? { onChanged }
    fileprivate var _onEnded: ((Value) -> Void)? { onEnded }
}

public extension View {
    func gesture(_ gesture: DragGesture) -> some View {
        DragGestureModifier(content: self, gesture: gesture)
    }
}

@MainActor
private struct DragGestureModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let gesture: DragGesture

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! DragGestureElement
            control.minimumDistance = gesture._minimumDistance
            control.onChanged = gesture._onChanged
            control.onEnded = gesture._onEnded
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? DragGestureElement {
            existing.minimumDistance = gesture._minimumDistance
            existing.onChanged = gesture._onChanged
            existing.onEnded = gesture._onEnded
            return existing
        }
        let wrapper = DragGestureElement(
            minimumDistance: gesture._minimumDistance,
            onChanged: gesture._onChanged,
            onEnded: gesture._onEnded
        )
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }
}

@MainActor
private final class DragGestureElement: Element {
    var minimumDistance: Int
    var onChanged: ((DragGesture.Value) -> Void)?
    var onEnded: ((DragGesture.Value) -> Void)?

    private var startAbsolute: Position?
    private var lastValue: DragGesture.Value?
    private var didPassMinimum = false

    init(
        minimumDistance: Int,
        onChanged: ((DragGesture.Value) -> Void)?,
        onEnded: ((DragGesture.Value) -> Void)?
    ) {
        self.minimumDistance = minimumDistance
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    override func size(proposedSize: Size) -> Size {
        children[0].size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        children[0].layout(size: size)
    }

    override func hitTest(position: Position) -> Element? {
        let local = position - layer.frame.position
        guard local.column >= 0, local.line >= 0,
              local.column < layer.frame.size.width,
              local.line < layer.frame.size.height else {
            return nil
        }
        if let childHit = children.reversed().compactMap({ $0.hitTest(position: local) }).first {
            return childHit
        }
        return self
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        switch event.type {
        case .pressed(.left):
            startAbsolute = event.position
            lastValue = makeValue(at: event.position)
            didPassMinimum = minimumDistance == 0
            window?.mouseCapture = self
            if didPassMinimum {
                onChanged?(lastValue!)
            }
        case .move:
            guard startAbsolute != nil else {
                super.handleMouseEvent(event)
                return
            }
            let value = makeValue(at: event.position)
            lastValue = value
            if !didPassMinimum {
                let dx = abs(value.translation.width.intValue)
                let dy = abs(value.translation.height.intValue)
                if max(dx, dy) >= minimumDistance {
                    didPassMinimum = true
                }
            }
            if didPassMinimum {
                onChanged?(value)
            }
        case .released(.left):
            if window?.mouseCapture === self {
                window?.mouseCapture = nil
            }
            if (lastValue != nil || startAbsolute != nil),
               didPassMinimum || minimumDistance == 0 {
                onEnded?(makeValue(at: event.position))
            }
            startAbsolute = nil
            lastValue = nil
            didPassMinimum = false
        default:
            super.handleMouseEvent(event)
        }
    }

    private func makeValue(at location: Position) -> DragGesture.Value {
        let start = startAbsolute ?? location
        let translation = Size(
            width: location.column - start.column,
            height: location.line - start.line
        )
        return DragGesture.Value(
            startLocation: start,
            location: location,
            translation: translation
        )
    }
}
