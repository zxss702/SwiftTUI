import Foundation

/// Layout / focus / hit-test / paint host in the element tree.
/// Not every view-graph node creates an element (e.g. ForEach).
@MainActor class Element: LayerDrawing {
    private(set) var children: [Element] = []
    private(set) var parent: Element?

    private var index: Int = 0

    var window: Window?
    private(set) lazy var layer: Layer = makeLayer()

    var root: Element { parent?.root ?? self }

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

    /// Soft caret in window coordinates, or `nil` when clipped away by an ancestor
    /// (e.g. ScrollView viewport). Matches `Layer.draw` clip nesting so the HW
    /// cursor is not left on content that replaced a scrolled-off field.
    var absoluteCursorPosition: Position? {
        guard let local = cursorPosition else { return nil }
        var point = local
        var walk: Element? = self
        while let current = walk {
            let bounds = Rect(position: .zero, size: current.layer.frame.size)
            guard !current.layer.frame.size.isEmpty, bounds.contains(point) else { return nil }
            guard let parent = current.parent else { break }
            point = point + current.layer.frame.position
            walk = parent
        }
        return absoluteFrame.position + local
    }

    var isHovered: Bool = false {
        didSet {
            if isHovered != oldValue {
                hoveredStateDidChange()
            }
        }
    }

    func hoveredStateDidChange() {}

    func addSubview(_ view: Element, at index: Int) {
        invalidateSizeCacheUpward()
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
        let removing = children[index]
        window?.resignInteraction(in: removing)
        removing.willRemoveFromParent()
        assignWindow(nil, to: removing)
        removing.parent = nil
        self.children.remove(at: index)
        layer.removeLayer(at: index)
        invalidateSizeCacheUpward()
        for i in index ..< children.count {
            children[i].index = i
        }
    }

    /// Keep `children[index]` identity-aligned with the view-graph element after an update.
    func syncChild(_ child: Element, at index: Int = 0) {
        if index < children.count {
            if children[index] !== child {
                removeSubview(at: index)
                addSubview(child, at: index)
            }
        } else {
            addSubview(child, at: index)
        }
    }

    /// Align `children[offset..<]` with `contentNode.element(at:)` after a content update
    /// (covers same-index identity swaps that insert/remove callbacks miss).
    func reconcileChildren(from contentNode: Node, offset: Int = 0) {
        let count = contentNode.size
        while children.count > offset + count {
            removeSubview(at: children.count - 1)
        }
        for i in 0 ..< count {
            syncChild(contentNode.element(at: i), at: offset + i)
        }
    }

    func willRemoveFromParent() {
        for child in children {
            child.willRemoveFromParent()
        }
    }

    private func assignWindow(_ window: Window?, to control: Element) {
        control.window = window
        for child in control.children {
            assignWindow(window, to: child)
        }
    }

    func isDescendant(of control: Element) -> Bool {
        guard let parent else { return false }
        return control === parent || parent.isDescendant(of: control)
    }

    func makeLayer() -> Layer {
        let layer = Layer()
        layer.content = self
        return layer
    }

    // MARK: - Layout

    private var sizeCacheKey: Size?
    private var sizeCacheValue: Size?

    func size(proposedSize: Size) -> Size {
        proposedSize
    }

    func sizeCached(proposedSize: Size) -> Size {
        if sizeCacheKey == proposedSize, let sizeCacheValue {
            return sizeCacheValue
        }
        let result = size(proposedSize: proposedSize)
        sizeCacheKey = proposedSize
        sizeCacheValue = result
        return result
    }

    /// Invalidate this element's size cache and bubble to ancestors.
    func invalidateSizeCacheUpward() {
        sizeCacheKey = nil
        sizeCacheValue = nil
        parent?.invalidateSizeCacheUpward()
    }

    /// Full-tree size-cache clear (resize / forced relayout).
    func invalidateSizeCache() {
        sizeCacheKey = nil
        sizeCacheValue = nil
        for child in children {
            child.invalidateSizeCache()
        }
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

    var layoutPriority: Double { 0 }

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

    /// Character input for the focused leaf. Default is a no-op — never broadcast
    /// to children (keys are delivered only to `Window.firstResponder`).
    func handleEvent(_ char: Character) {}

    /// Key input for the focused leaf. Default forwards printable chars to
    /// `handleEvent`; never fans out to the subtree.
    func handleKeyEvent(_ event: KeyEvent) {
        if let char = event.character {
            handleEvent(char)
        }
    }

    /// Editors that stage Binding writes until the next frame.
    var needsBindingCommit: Bool { false }
    func commitBindingIfNeeded() {}

    func handleMouseEvent(_ event: MouseEvent) {
        parent?.handleMouseEvent(event)
    }

    func hitTest(position: Position) -> Element? {
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

    var focusableFlag: Bool = true

    var focusRegistration: FocusRegistration?

    // MARK: - Selection

    var selectable: Bool { false }

    var canReceiveFocus: Bool { selectable && focusableFlag }

    var firstSelectableElement: Element? {
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

