import Foundation

@MainActor
public struct Slider<Label: View>: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double?
    let label: Label?

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double? = nil
    ) where Label == EmptyView {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.label = nil
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.label = label()
    }

    public var body: some View {
        HStack(spacing: 1) {
            if let label { label }
            SliderTrack(value: $value, bounds: bounds, step: step)
                .frame(maxWidth: .infinity)
        }
    }
}

@MainActor
private struct SliderTrack: View, PrimitiveView {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double?
    @Environment(\.isEnabled) private var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.element = SliderElement(value: $value, bounds: bounds, step: step, isEnabled: isEnabled)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! SliderElement
        control.value = $value
        control.bounds = bounds
        control.step = step
        control.isEnabledFlag = isEnabled
        control.layer.invalidate()
    }
}

@MainActor
private final class SliderElement: Element {
    var value: Binding<Double>
    var bounds: ClosedRange<Double>
    var step: Double?
    var isEnabledFlag: Bool

    init(value: Binding<Double>, bounds: ClosedRange<Double>, step: Double?, isEnabled: Bool) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.isEnabledFlag = isEnabled
    }

    /// Drag/click only — not a keyboard first-responder (SwiftUI-shaped focus).
    override var selectable: Bool { false }
    override var claimsPointerCapture: Bool { isEnabledFlag }
    override var retainsPointerCaptureAfterPress: Bool { isEnabledFlag }

    override func size(proposedSize: Size) -> Size {
        if proposedSize.width == .infinity {
            return Size(width: 20, height: 1)
        }
        return Size(width: max(proposedSize.width, 1), height: 1)
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
        let span = bounds.upperBound - bounds.lowerBound
        let delta = step ?? max(span / 20, 0.01)
        if event.keycode == VTKeyCode.left {
            setValue(value.wrappedValue - delta)
        } else if event.keycode == VTKeyCode.right {
            setValue(value.wrappedValue + delta)
        } else {
            super.handleKeyEvent(event)
        }
    }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        guard isEnabledFlag, event.button == .left else { return false }
        switch event.phase {
        case .began, .moved, .ended:
            let local = event.position - absoluteFrame.position
            let width = max(1, layer.frame.size.width.intValue - 1)
            let ratio = min(1, max(0, Double(local.column.intValue) / Double(width)))
            setValue(bounds.lowerBound + ratio * (bounds.upperBound - bounds.lowerBound))
            return true
        case .cancelled:
            return true
        }
    }

    override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
        false
    }

    override func draw(into buffer: inout ScreenBuffer) {
        let width = max(2, layer.frame.size.width.intValue)
        let span = bounds.upperBound - bounds.lowerBound
        let ratio = span > 0 ? (value.wrappedValue - bounds.lowerBound) / span : 0
        let thumb = min(width - 1, max(0, Int((Double(width - 1) * ratio).rounded())))
        for x in 0 ..< width {
            var cell = Cell(char: x == thumb ? "●" : "─")
            if !isEnabledFlag { cell.attributes.faint = true }
            buffer.setCell(cell, at: Position(column: Extended(x), line: 0))
        }
    }

    private func setValue(_ raw: Double) {
        var v = min(bounds.upperBound, max(bounds.lowerBound, raw))
        if let step, step > 0 {
            let n = ((v - bounds.lowerBound) / step).rounded()
            v = bounds.lowerBound + n * step
            v = min(bounds.upperBound, max(bounds.lowerBound, v))
        }
        value.wrappedValue = v
        layer.invalidate()
    }
}
