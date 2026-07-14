import Foundation

@MainActor
public struct Stepper<Label: View>: View {
    @Binding var value: Int
    let bounds: ClosedRange<Int>
    let step: Int
    let label: Label

    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
        step: Int = 1,
        @ViewBuilder label: () -> Label
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.label = label()
    }

    public init(
        _ title: String,
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
        step: Int = 1
    ) where Label == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.label = Text(title)
    }

    public var body: some View {
        HStack(spacing: 1) {
            label
            StepperControlView(value: $value, bounds: bounds, step: step)
        }
    }
}

@MainActor
private struct StepperControlView: View, PrimitiveView {
    @Binding var value: Int
    let bounds: ClosedRange<Int>
    let step: Int
    @Environment(\.isEnabled) private var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.element = StepperElement(value: $value, bounds: bounds, step: step, isEnabled: isEnabled)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! StepperElement
        control.value = $value
        control.bounds = bounds
        control.step = step
        control.isEnabledFlag = isEnabled
        control.layer.invalidate()
    }
}

@MainActor
private final class StepperElement: Element {
    var value: Binding<Int>
    var bounds: ClosedRange<Int>
    var step: Int
    var isEnabledFlag: Bool

    init(value: Binding<Int>, bounds: ClosedRange<Int>, step: Int, isEnabled: Bool) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.isEnabledFlag = isEnabled
    }

    override var selectable: Bool { isEnabledFlag }

    override func size(proposedSize: Size) -> Size {
        let label = "[\(value.wrappedValue)] − +"
        return Size(width: Extended(label.width), height: 1)
    }

    override func handleEvent(_ char: Character) {
        guard isEnabledFlag else { return }
        if char == "-" || char == "_" {
            adjust(-step)
        } else if char == "+" || char == "=" {
            adjust(step)
        }
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
        if event.keycode == VTKeyCode.left {
            adjust(-step)
        } else if event.keycode == VTKeyCode.right {
            adjust(step)
        } else {
            super.handleKeyEvent(event)
        }
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        guard isEnabledFlag else { return }
        if case .released(.left) = event.type {
            let local = event.position - absoluteFrame.position
            let mid = layer.frame.size.width / 2
            adjust(local.column < mid ? -step : step)
        } else {
            super.handleMouseEvent(event)
        }
    }

    override func draw(into buffer: inout ScreenBuffer) {
        let string = "[\(value.wrappedValue)] − +"
        var col = 0
        for ch in string {
            var cell = Cell(char: ch)
            if !isEnabledFlag { cell.attributes.faint = true }
            buffer.setCell(cell, at: Position(column: Extended(col), line: 0))
            col += ch.width
        }
    }

    private func adjust(_ delta: Int) {
        let next = min(bounds.upperBound, max(bounds.lowerBound, value.wrappedValue + delta))
        value.wrappedValue = next
        layer.invalidate()
    }
}
