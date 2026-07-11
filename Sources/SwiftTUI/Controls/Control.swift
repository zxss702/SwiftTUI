import Foundation

/// The basic layout object that can be created by a node. Not every node will
/// create a control (e.g. ForEach won't).
@MainActor class Control: LayerDrawing {
    private(set) var children: [Control] = []
    private(set) var parent: Control?

    private var index: Int = 0

    var window: Window?
    private(set) lazy var layer: Layer = makeLayer()

    var root: Control { parent?.root ?? self }
    
    var absoluteFrame: Rect {
        var pos = layer.frame.position
        var p = parent
        while let current = p {
            pos = pos + current.layer.frame.position
            p = current.parent
        }
        return Rect(position: pos, size: layer.frame.size)
    }
    
    var cursorPosition: Position? { nil }
    
    var isHovered: Bool = false {
        didSet {
            if isHovered != oldValue {
                hoveredStateDidChange()
            }
        }
    }
    
    func hoveredStateDidChange() {}

    func addSubview(_ view: Control, at index: Int) {
        self.children.insert(view, at: index)
        layer.addLayer(view.layer, at: index)
        view.parent = self
        assignWindow(window, to: view)
        for i in index ..< children.count {
            children[i].index = i
        }
        if let window = root.window, window.firstResponder == nil {
            if let responder = view.firstSelectableElement {
                window.setFirstResponder(responder)
            }
        }
    }

    func removeSubview(at index: Int) {
        if children[index].isFirstResponder || root.window?.firstResponder?.isDescendant(of: children[index]) == true {
            let fallback = root.firstSelectableElement
            // Prefer a sibling/ancestor selectable that is not inside the removed subtree.
            let next: Control?
            if let fallback, !fallback.isDescendant(of: children[index]), fallback !== children[index] {
                next = fallback
            } else {
                next = nil
            }
            root.window?.setFirstResponder(next)
        }
        children[index].willRemoveFromParent()
        assignWindow(nil, to: children[index])
        children[index].parent = nil
        self.children.remove(at: index)
        layer.removeLayer(at: index)
        for i in index ..< children.count {
            children[i].index = i
        }
    }

    /// 子树即将从父控件移除时调用（用于 onDisappear 等）。
    func willRemoveFromParent() {
        for child in children {
            child.willRemoveFromParent()
        }
    }

    /// 子树在 addSubview 时可能已有后代，需递归注入 window（否则面板内 Button 拿不到 popupPresenter）。
    private func assignWindow(_ window: Window?, to control: Control) {
        control.window = window
        for child in control.children {
            assignWindow(window, to: child)
        }
    }

    func isDescendant(of control: Control) -> Bool {
        guard let parent else { return false }
        return control === parent || parent.isDescendant(of: control)
    }

    func makeLayer() -> Layer {
        let layer = Layer()
        layer.content = self
        return layer
    }

    // MARK: - Layout

    func size(proposedSize: Size) -> Size {
        proposedSize
    }

    func layout(size: Size) {
        layer.frame.size = size
    }

    func horizontalFlexibility(height: Extended) -> Extended {
        let minSize = size(proposedSize: Size(width: 0, height: height))
        let maxSize = size(proposedSize: Size(width: .infinity, height: height))
        return maxSize.width - minSize.width
    }

    func verticalFlexibility(width: Extended) -> Extended {
        let minSize = size(proposedSize: Size(width: width, height: 0))
        let maxSize = size(proposedSize: Size(width: width, height: .infinity))
        return maxSize.height - minSize.height
    }

    /// 同栈内更高优先级的子视图优先获得空间（对齐 SwiftUI）。
    var layoutPriority: Double { 0 }

    /// Propagates the visible scroll window to lazy descendants.
    /// Returns `true` if any lazy control rebuilt its children and needs layout.
    @discardableResult
    func updateVisibleRegion(offset: Extended, height: Extended) -> Bool {
        var needsLayout = false
        for child in children {
            if child.updateVisibleRegion(offset: offset - child.layer.frame.position.line, height: height) {
                needsLayout = true
            }
        }
        return needsLayout
    }

    // MARK: - Drawing

    func draw(into buffer: inout ScreenBuffer) {}

    // MARK: - Event handling

    func handleEvent(_ char: Character) {
        for subview in children {
            subview.handleEvent(char)
        }
    }

    func handleKeyEvent(_ event: KeyEvent) {
        if let char = event.character {
            handleEvent(char)
        } else {
            for subview in children {
                subview.handleKeyEvent(event)
            }
        }
    }

    func handleMouseEvent(_ event: MouseEvent) {
        parent?.handleMouseEvent(event)
    }

    func hitTest(position: Position) -> Control? {
        let localPosition = position - layer.frame.position
        
        guard localPosition.column >= 0, localPosition.line >= 0,
              localPosition.column < layer.frame.size.width,
              localPosition.line < layer.frame.size.height else {
            return nil
        }
        
        for child in children.reversed() {
            if let hit = child.hitTest(position: localPosition) {
                return hit
            }
        }
        return self
    }

    func becomeFirstResponder() {
        scroll(to: .zero)
    }

    func resignFirstResponder() {}

    var isFirstResponder: Bool { root.window?.firstResponder === self }

    /// Set by `.focusable(false)` to opt out of keyboard/mouse focus.
    var focusableFlag: Bool = true

    /// Registration installed by `.focused` / `.focused(_:equals:)`.
    var focusRegistration: FocusRegistration?

    // MARK: - Selection

    var selectable: Bool { false }

    /// Whether this control may become `Window.firstResponder`.
    var canReceiveFocus: Bool { selectable && focusableFlag }

    var firstSelectableElement: Control? {
        if canReceiveFocus { return self }
        for control in children {
            if let element = control.firstSelectableElement { return element }
        }
        return nil
    }


    // MARK: - Scrolling

    func scroll(to position: Position) {
        parent?.scroll(to: position + layer.frame.position)
    }

}
