import Foundation

// MARK: - isEnabled

private struct IsEnabledEnvironmentKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

public extension EnvironmentValues {
    var isEnabled: Bool {
        get { self[IsEnabledEnvironmentKey.self] }
        set { self[IsEnabledEnvironmentKey.self] = newValue }
    }
}

public extension View {
    /// 禁用交互；子树 `isEnabled == false`，并灰显、吞掉命中与按键。
    func disabled(_ disabled: Bool) -> some View {
        DisabledModifier(content: self, disabled: disabled)
    }
}

@MainActor
private struct DisabledModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let disabled: Bool

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
        if disabled {
            node.environment = { $0.isEnabled = false }
        }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.environment = disabled ? { $0.isEnabled = false } : nil
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! DisabledElement
            control.isDisabled = disabled
            control.layer.invalidate()
        }
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent as? DisabledElement {
            existing.isDisabled = disabled
            return existing
        }
        let wrapper = DisabledElement(isDisabled: disabled)
        wrapper.addSubview(control, at: 0)
        node.elements?.add(wrapper)
        return wrapper
    }

    private final class DisabledElement: Element {
        var isDisabled: Bool

        init(isDisabled: Bool) {
            self.isDisabled = isDisabled
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
        }

        override func hitTest(position: Position) -> Element? {
            guard isDisabled else {
                return super.hitTest(position: position)
            }
            let local = position - layer.frame.position
            guard local.column >= 0, local.line >= 0,
                  local.column < layer.frame.size.width,
                  local.line < layer.frame.size.height else {
                return nil
            }
            // 吞掉命中，不交给可交互子控件
            return self
        }

        override func dispatchMouseEvent(_ event: MouseEvent) -> Bool {
            guard absoluteFrame.contains(event.position) else { return false }
            if isDisabled { return true }
            return super.dispatchMouseEvent(event)
        }

        override func handleEvent(_ char: Character) {
            if isDisabled { return }
            super.handleEvent(char)
        }

        override func handleKeyEvent(_ event: KeyEvent) {
            if isDisabled { return }
            super.handleKeyEvent(event)
        }

        override var firstSelectableElement: Element? {
            isDisabled ? nil : super.firstSelectableElement
        }

        override func makeLayer() -> Layer {
            DisabledLayer(isDisabled: { [weak self] in self?.isDisabled ?? false })
        }
    }

    private final class DisabledLayer: Layer {
        let isDisabled: () -> Bool

        init(isDisabled: @escaping () -> Bool) {
            self.isDisabled = isDisabled
        }

        override func draw(into buffer: inout ScreenBuffer) {
            super.draw(into: &buffer)
            guard isDisabled() else { return }
            for y in 0 ..< frame.size.height.intValue {
                for x in 0 ..< frame.size.width.intValue {
                    let pos = Position(column: Extended(x), line: Extended(y))
                    guard var cell = buffer.cell(at: pos) else { continue }
                    cell.attributes.faint = true
                    cell.attributes.bold = false
                    buffer.setCell(cell, at: pos)
                }
            }
        }
    }
}
