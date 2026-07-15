import Foundation

// MARK: - Button

@MainActor public struct Button<Label: View>: View, PrimitiveView {
    let label: VStack<Label>
    let hover: () -> Void
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.buttonDismissesPresentation) private var buttonDismissesPresentation

    public init(action: @escaping () -> Void, hover: @escaping () -> Void = {}, @ViewBuilder label: () -> Label) {
        self.label = VStack(content: label())
        self.action = action
        self.hover = hover
    }

    public init(_ text: String, hover: @escaping () -> Void = {}, action: @escaping () -> Void) where Label == Text {
        self.label = VStack(content: Text(text))
        self.action = action
        self.hover = hover
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.addNode(at: 0, Node(view: label.view))
        let control = ButtonElement(action: action, hover: hover)
        control.label = node.children[0].element(at: 0)
        control.addSubview(control.label, at: 0)
        control.onActivate = makeOnActivate()
        node.element = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        node.children[0].update(using: label.view)
        let control = node.element as! ButtonElement
        let newLabel = node.children[0].element(at: 0)
        control.label = newLabel
        control.syncChild(newLabel)
        control.action = action
        control.hover = hover
        control.onActivate = makeOnActivate()
    }

    private func makeOnActivate() -> () -> Void {
        let action = self.action
        let dismiss = self.dismiss
        let autoDismiss = buttonDismissesPresentation
        return {
            action()
            if autoDismiss {
                dismiss()
            }
        }
    }

    private class ButtonElement: Element {
        var action: () -> Void
        var hover: () -> Void
        var onActivate: (() -> Void)?
        var label: Element!

        init(action: @escaping () -> Void, hover: @escaping () -> Void) {
            self.action = action
            self.hover = hover
        }

        /// Clickable but not a keyboard first-responder.
        override var selectable: Bool { false }
        override var claimsPointerCapture: Bool { true }

        override func size(proposedSize: Size) -> Size {
            return label.size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            self.label.layout(size: size)
        }

        override func handleEvent(_ char: Character) {
            if char == "\n" || char == " " {
                performAction()
            }
        }

        /// UIKit-inspired gesture: fire on `.ended` for the same hit-tested
        /// owner that received `.began`. Terminal release coords often drift a
        /// cell or two off the button — do **not** require `contains` (that
        /// made clicks miss while tracking was true).
        private var tracking = false

        override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
            guard event.button == .left else { return false }
            switch event.phase {
            case .began:
                tracking = true
                return true
            case .moved:
                return tracking
            case .ended:
                let shouldFire = tracking
                tracking = false
                if shouldFire {
                    performAction()
                }
                return true
            case .cancelled:
                tracking = false
                return true
            }
        }

        override func pointerGestureCancelled() {
            tracking = false
        }

        private func performAction() {
            if let onActivate {
                onActivate()
            } else {
                action()
            }
        }

        override func hoveredStateDidChange() {
            if isHovered { hover() }
        }
    }
}
