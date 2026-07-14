import Foundation

@MainActor class Window: LayerDrawing {
    private(set) lazy var layer: Layer = makeLayer()

    private(set) var elements: [Element] = []

    private(set) var firstResponder: Element?

    /// 当前悬停叶控件；与 `firstResponder` / `mouseCapture` 同属窗口交互指针。
    private(set) weak var hoveredElement: Element?

    /// 拖动手势等：按下后捕获 move/release，避免 hitTest 随光标漂移。
    weak var mouseCapture: Element?

    /// 应用级弹出层；由 `Application` 注入，供弹出菜单等 Element 回调使用。
    weak var popupPresenter: PopupPresenter?

    func addElement(_ control: Element) {
        control.window = self
        self.elements.append(control)
        layer.addLayer(control.layer, at: 0)
    }

    /// Single entry for focus changes so `@FocusState` / `.focused` stay in sync.
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
    }

    func setHoveredElement(_ control: Element?) {
        guard hoveredElement !== control else { return }

        func ancestors(from control: Element?) -> [Element] {
            var path: [Element] = []
            var current = control
            while let node = current {
                path.append(node)
                current = node.parent
            }
            return path
        }

        let oldPath = ancestors(from: hoveredElement)
        let newPath = ancestors(from: control)
        let newIDs = Set(newPath.map { ObjectIdentifier($0) })
        let oldIDs = Set(oldPath.map { ObjectIdentifier($0) })

        for item in oldPath where !newIDs.contains(ObjectIdentifier(item)) {
            item.isHovered = false
        }
        for item in newPath.reversed() where !oldIDs.contains(ObjectIdentifier(item)) {
            item.isHovered = true
        }
        hoveredElement = control
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
            mouseCapture = nil
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
