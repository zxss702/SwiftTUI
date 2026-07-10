import Foundation

/// 不确定进度用 spinner；确定进度用 `████░░` 条。
@MainActor
public struct ProgressView<Label: View>: View {
    private enum Kind {
        case indeterminate
        case determinate(total: Double, value: Double)
    }

    private let kind: Kind
    private let label: Label?

    public init() where Label == EmptyView {
        self.kind = .indeterminate
        self.label = nil
    }

    public init(@ViewBuilder label: () -> Label) {
        self.kind = .indeterminate
        self.label = label()
    }

    public init<V: BinaryFloatingPoint>(value: V, total: V = 1) where Label == EmptyView {
        self.kind = .determinate(total: Double(total), value: Double(value))
        self.label = nil
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        total: V = 1,
        @ViewBuilder label: () -> Label
    ) {
        self.kind = .determinate(total: Double(total), value: Double(value))
        self.label = label()
    }

    public var body: some View {
        switch kind {
        case .indeterminate:
            HStack(spacing: 1) {
                SpinnerView()
                if let label { label }
            }
        case .determinate(let total, let value):
            HStack(spacing: 1) {
                DeterminateBar(value: value, total: total)
                    .frame(maxWidth: .infinity)
                if let label { label }
            }
        }
    }
}

@MainActor
private struct DeterminateBar: View, PrimitiveView {
    let value: Double
    let total: Double

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.control = DeterminateBarControl(value: value, total: total)
    }

    func updateNode(_ node: Node) {
        node.view = self
        let control = node.control as! DeterminateBarControl
        control.value = value
        control.total = total
        control.layer.invalidate()
    }

    private final class DeterminateBarControl: Control {
        var value: Double
        var total: Double

        init(value: Double, total: Double) {
            self.value = value
            self.total = total
        }

        override func size(proposedSize: Size) -> Size {
            if proposedSize.width == .infinity {
                return Size(width: 20, height: 1)
            }
            return Size(width: max(proposedSize.width, 1), height: 1)
        }

        override func draw(into buffer: inout ScreenBuffer) {
            let width = max(1, layer.frame.size.width.intValue)
            let ratio = total > 0 ? min(1, max(0, value / total)) : 0
            let filled = Int((Double(width) * ratio).rounded(.down))
            for x in 0 ..< width {
                let char: Character = x < filled ? "█" : "░"
                buffer.setCell(Cell(char: char), at: Position(column: Extended(x), line: 0))
            }
        }
    }
}

@MainActor
private struct SpinnerView: View, PrimitiveView {
    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.control = SpinnerControl()
    }

    func updateNode(_ node: Node) {
        node.view = self
    }

    private final class SpinnerControl: Control {
        private static let frames: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        private var index = 0
        private var timer: Timer?

        override func size(proposedSize: Size) -> Size {
            Size(width: 1, height: 1)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            startIfNeeded()
        }

        override func willRemoveFromParent() {
            timer?.invalidate()
            timer = nil
            super.willRemoveFromParent()
        }

        override func draw(into buffer: inout ScreenBuffer) {
            let char = Self.frames[index % Self.frames.count]
            buffer.setCell(Cell(char: char), at: .zero)
        }

        private func startIfNeeded() {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.index = (self.index + 1) % Self.frames.count
                    self.layer.invalidate()
                    self.layer.renderer?.application?.scheduleUpdate()
                }
            }
        }
    }
}
