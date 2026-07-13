import Foundation

@MainActor class Window: LayerDrawing {
    private(set) lazy var layer: Layer = makeLayer()

    private(set) var controls: [Control] = []

    private(set) var firstResponder: Control?

    /// 当前悬停叶控件；与 `firstResponder` / `mouseCapture` 同属窗口交互指针。
    private(set) weak var hoveredControl: Control?

    /// 拖动手势等：按下后捕获 move/release，避免 hitTest 随光标漂移。
    weak var mouseCapture: Control?

    /// 应用级弹出层；由 `Application` 注入，供弹出菜单等 Control 回调使用。
    weak var popupPresenter: PopupPresenter?

    func addControl(_ control: Control) {
        control.window = self
        self.controls.append(control)
        layer.addLayer(control.layer, at: 0)
    }

    /// Single entry for focus changes so `@FocusState` / `.focused` stay in sync.
    func setFirstResponder(_ control: Control?) {
        let next: Control?
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

    func setHoveredControl(_ control: Control?) {
        guard hoveredControl !== control else { return }

        func ancestors(from control: Control?) -> [Control] {
            var path: [Control] = []
            var current = control
            while let node = current {
                path.append(node)
                current = node.parent
            }
            return path
        }

        let oldPath = ancestors(from: hoveredControl)
        let newPath = ancestors(from: control)
        let newIDs = Set(newPath.map { ObjectIdentifier($0) })
        let oldIDs = Set(oldPath.map { ObjectIdentifier($0) })

        for item in oldPath where !newIDs.contains(ObjectIdentifier(item)) {
            item.isHovered = false
        }
        for item in newPath.reversed() where !oldIDs.contains(ObjectIdentifier(item)) {
            item.isHovered = true
        }
        hoveredControl = control
    }

    /// 子树即将从控件树卸下时，释放指向该子树的交互指针（focus / hover / capture）。
    /// 必须在 `assignWindow(nil)` / `parent = nil` 之前调用，以便 leave 回调时视图仍挂树。
    func resignInteraction(in subtree: Control) {
        if let focused = firstResponder,
           focused === subtree || focused.isDescendant(of: subtree) {
            let fallback = controls.first?.firstSelectableElement
            let next: Control?
            if let fallback, !fallback.isDescendant(of: subtree), fallback !== subtree {
                next = fallback
            } else {
                next = nil
            }
            setFirstResponder(next)
        }

        if let hovered = hoveredControl,
           hovered === subtree || hovered.isDescendant(of: subtree) {
            setHoveredControl(nil)
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
