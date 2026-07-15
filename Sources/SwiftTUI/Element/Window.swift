import Foundation

/// Weak box for hover-path snapshots (survivors get leave after leaf rebuilds).
@MainActor
struct WeakElementRef {
    weak var value: Element?

    init(_ value: Element?) {
        self.value = value
    }
}

@MainActor class Window: LayerDrawing {
    private(set) lazy var layer: Layer = makeLayer()

    private(set) var elements: [Element] = []

    private(set) var firstResponder: Element?

    /// 当前悬停叶控件；与 `firstResponder` / `mouseCapture` 同属窗口交互指针。
    private(set) weak var hoveredElement: Element?

    /// Weak snapshot of the hovered path (leaf→root). Leave must reach the
    /// surviving ancestors (OnHover wrappers) even when the leaf element was
    /// rebuilt and the weak `hoveredElement` already died.
    private var hoverPathRefs: [WeakElementRef] = []

    /// Hover leaf frozen under an open presentation (skipped leave); cleared on dismiss sync.
    private weak var presentationFrozenHover: Element?

    /// 拖动手势等：按下后捕获 move/release，避免 hitTest 随光标漂移。
    weak var mouseCapture: Element?

    /// Active UIKit-style pointer gesture (began → moved → ended).
    var pointerGesture: PointerGestureSession?

    /// Clear capture and notify the previous owner (gesture / press-armed reset).
    func clearMouseCapture() {
        guard let capture = mouseCapture else { return }
        mouseCapture = nil
        capture.pointerCaptureEnded()
    }

    /// Cancel any in-flight pointer gesture and notify the owner.
    func cancelPointerGesture() {
        if let target = pointerGesture?.target {
            _ = target.pointerGesture(
                PointerGestureEvent(phase: .cancelled, position: pointerGesture!.start, button: pointerGesture!.button)
            )
            target.pointerGestureCancelled()
        }
        pointerGesture = nil
        clearMouseCapture()
    }

    /// 应用级弹出层；由 `Application` 注入，供弹出菜单等 Element 回调使用。
    weak var popupPresenter: PopupPresenter?

    func addElement(_ control: Element) {
        control.window = self
        self.elements.append(control)
        layer.addLayer(control.layer, at: 0)
    }

    /// Single entry for focus changes so `@FocusState` / `.focused` stay in sync.
    ///
    /// Only text-entry controls (`canReceiveFocus`) may become first responder —
    /// Buttons / scrollers / toggles are rejected (SwiftUI-shaped).
    func setFirstResponder(_ control: Element?) {
        let next: Element?
        if let control, control.canReceiveFocus {
            next = control
        } else {
            next = nil
        }
        guard firstResponder !== next else { return }

        let previous = firstResponder
        previous?.resignFirstResponder()
        previous?.focusRegistration?.notifyResignFirstResponder()

        firstResponder = next

        next?.becomeFirstResponder()
        next?.focusRegistration?.notifyBecomeFirstResponder()
        // Soft caret follows first responder; non-inputs never become FR so the
        // hardware cursor is only placed for TextField / TextEditor / SecureField.
        layer.rootRenderer?.application?.requestPaint()
    }

    func setHoveredElement(_ control: Element?) {
        // Proceed when the leaf died (weak → nil) but stale hovered ancestors
        // remain — they still owe a leave.
        let staleHoverPath = hoveredElement == nil && hoverPathRefs.contains { $0.value != nil }
        guard hoveredElement !== control || staleHoverPath else { return }

        func ancestors(from control: Element?) -> [Element] {
            var path: [Element] = []
            var current = control
            while let node = current {
                path.append(node)
                current = node.parent
            }
            return path
        }

        let presentationOpen = popupPresenter?.isPresented == true
        let isolationRoot = popupPresenter?.top?.hostElement

        // Old path from the stored snapshot: survives leaf deallocation.
        let oldPath = hoverPathRefs.compactMap(\.value)
        let newPath = ancestors(from: control)
        let newIDs = Set(newPath.map { ObjectIdentifier($0) })
        let oldIDs = Set(oldPath.map { ObjectIdentifier($0) })

        // Presentation just closed: finish any skipped leave on the frozen leaf.
        if !presentationOpen, let frozen = presentationFrozenHover {
            for item in ancestors(from: frozen) where !newIDs.contains(ObjectIdentifier(item)) {
                item.isHovered = false
            }
            presentationFrozenHover = nil
        }

        for item in oldPath where !newIDs.contains(ObjectIdentifier(item)) {
            // Freeze underlying hover for the whole time a presentation is open,
            // even before the floating host element is mounted.
            if presentationOpen {
                let inPresented = isolationRoot.map { item === $0 || item.isDescendant(of: $0) } ?? false
                if !inPresented {
                    if presentationFrozenHover == nil { presentationFrozenHover = item }
                    continue
                }
            }
            item.isHovered = false
        }
        for item in newPath.reversed() where !oldIDs.contains(ObjectIdentifier(item)) {
            if presentationOpen {
                let inPresented = isolationRoot.map { item === $0 || item.isDescendant(of: $0) } ?? false
                if !inPresented { continue }
            }
            item.isHovered = true
        }
        hoveredElement = control
        hoverPathRefs = newPath.map { WeakElementRef($0) }
    }

    /// 子树即将从控件树卸下时，释放指向该子树的交互指针（focus / hover / capture）。
    /// 必须在 `assignWindow(nil)` / `parent = nil` 之前调用，以便 leave 回调时视图仍挂树。
    func resignInteraction(in subtree: Element) {
        if let focused = firstResponder,
           focused === subtree || focused.isDescendant(of: subtree) {
            let fallback = elements.first?.firstSelectableElement
            let next: Element?
            if let fallback, !fallback.isDescendant(of: subtree), fallback !== subtree {
                next = fallback
            } else {
                next = nil
            }
            setFirstResponder(next)
        }

        if let hovered = hoveredElement,
           hovered === subtree || hovered.isDescendant(of: subtree) {
            setHoveredElement(nil)
        }

        if let capture = mouseCapture,
           capture === subtree || capture.isDescendant(of: subtree) {
            clearMouseCapture()
        }
    }

    private func makeLayer() -> Layer {
        let layer = Layer()
        layer.content = self
        return layer
    }

    func draw(into buffer: inout ScreenBuffer) {
        let cell = Cell(char: " ")
        for y in 0 ..< layer.frame.size.height.intValue {
            for x in 0 ..< layer.frame.size.width.intValue {
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
            }
        }
    }
}
