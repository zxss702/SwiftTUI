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

    /// Absolute frame of the nearest enclosing scroll viewport, if any.
    /// Used by text-selection edge auto-scroll: a `.selectable()` region inside
    /// a `ScrollView` is often taller than the visible viewport, so edge
    /// detection must use the viewport — not the region's own frame.
    var scrollViewportAbsoluteFrame: Rect? { parent?.scrollViewportAbsoluteFrame }

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
        // 惰性 ForEach 不再经 `Node.addNode` → `insertElement` 通知容器；
        // `reconcileChildren` / Lazy 挂载只走这里。不 requestLayout 时，
        // Menu 叠层会停在 0×0（toolbarTitleMenu / Menu 项全部点不了）。
        layer.rootRenderer?.application?.requestLayout()
    }

    func removeSubview(at index: Int) {
        guard children.indices.contains(index) else { return }
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
        layer.rootRenderer?.application?.requestLayout()
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
    ///
    /// `if hover { Menu }` / Optional / `_ConditionalView` rebuilds change child
    /// identity here. Clearing hover in `removeSubview` would fire a spurious
    /// `onHover(false)`, unmount the Menu again, and empty an open popup.
    /// Suppress resign for the swap; Application re-hit-tests at frame end.
    func reconcileChildren(from contentNode: Node, offset: Int = 0) {
        let count = contentNode.size
        var willMutate = children.count > offset + count
        if !willMutate {
            for i in 0 ..< count {
                let expected = contentNode.element(at: i)
                let index = offset + i
                if index >= children.count || children[index] !== expected {
                    willMutate = true
                    break
                }
            }
        }
        let window = root.window
        let previousSuppress = window?.suppressHoverResign ?? false
        if willMutate {
            window?.suppressHoverResign = true
        }
        defer { window?.suppressHoverResign = previousSuppress }

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

    func assignWindow(_ window: Window?, to control: Element) {
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
    /// Flexibility is derived from `size()` and is queried repeatedly by stack
    /// layout sorting; cache per query dimension, invalidated with the size cache.
    private var verticalFlexCache: (width: Extended, value: Extended)?
    private var horizontalFlexCache: (height: Extended, value: Extended)?

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
        verticalFlexCache = nil
        horizontalFlexCache = nil
        parent?.invalidateSizeCacheUpward()
    }

    /// Full-tree size-cache clear (resize / forced relayout).
    func invalidateSizeCache() {
        sizeCacheKey = nil
        sizeCacheValue = nil
        verticalFlexCache = nil
        horizontalFlexCache = nil
        for child in children {
            child.invalidateSizeCache()
        }
    }

    func layout(size: Size) {
        layer.frame.size = size
    }

    func horizontalFlexibility(height: Extended) -> Extended {
        if let cache = horizontalFlexCache, cache.height == height { return cache.value }
        let minSize = size(proposedSize: Size(width: 0, height: height))
        let maxSize = size(proposedSize: Size(width: .infinity, height: height))
        let value = maxSize.width - minSize.width
        horizontalFlexCache = (height, value)
        return value
    }

    func verticalFlexibility(width: Extended) -> Extended {
        if let cache = verticalFlexCache, cache.width == width { return cache.value }
        let minSize = size(proposedSize: Size(width: width, height: 0))
        let maxSize = size(proposedSize: Size(width: width, height: .infinity))
        let value = maxSize.height - minSize.height
        verticalFlexCache = (width, value)
        return value
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

    /// Bulk text from coalesced paste / typed burst. Default inserts one
    /// character at a time via `handleEvent`.
    func handleTextInput(_ string: String) {
        for char in string {
            handleEvent(char)
        }
    }

    /// Editors that stage Binding writes until the next frame.
    var needsBindingCommit: Bool { false }
    func commitBindingIfNeeded() {}

    /// Consume a mouse event at this node. Return `true` to stop top-down delivery.
    /// Prefer ``pointerGesture(_:)`` for press/move/release click handling.
    func consumeMouseEvent(_ event: MouseEvent) -> Bool { false }

    /// UIKit-style pointer gesture after `Window` hit-tests the owner.
    /// Return `true` when this node owns / handled the phase.
    func pointerGesture(_ event: PointerGestureEvent) -> Bool { false }

    /// When `true`, this element takes over pointer gestures for its whole
    /// subtree (text selection). Clean clicks are re-forwarded to the inner
    /// control by the interceptor, so taps / buttons keep working.
    var interceptsPointerGestures: Bool { false }

    /// Hit-test leaf, then climb to the pointer owner (Button / editor / …).
    func pointerGestureTarget(at absolutePosition: Position) -> Element? {
        guard let leaf = hitTest(position: absolutePosition) else { return nil }
        let normal = leaf.pointerTargetOnClick ?? leaf
        // A `.selectable()` ancestor owns drags over its subtree — except when
        // the press lands on a focusable text control, whose own editing
        // selection handles dragging.
        if !normal.canReceiveFocus {
            var current: Element? = leaf
            while let node = current {
                if node.interceptsPointerGestures { return node }
                current = node.parent
            }
        }
        return normal
    }

    /// The pointer owner ignoring selection interception (used by the
    /// interceptor to re-forward clean clicks).
    func pointerGestureTargetBypassingInterception(at absolutePosition: Position) -> Element? {
        guard let leaf = hitTest(position: absolutePosition) else { return nil }
        return leaf.pointerTargetOnClick ?? leaf
    }

    /// Top-down mouse delivery: front-most child under the point first, then self.
    /// Returns `true` when some node along the path handled the event.
    @discardableResult
    func dispatchMouseEvent(_ event: MouseEvent) -> Bool {
        guard absoluteFrame.contains(event.position) else { return false }
        for child in children.reversed() {
            if child.dispatchMouseEvent(event) { return true }
        }
        return consumeMouseEvent(event)
    }

    /// Legacy entry: prefer ``consumeMouseEvent``; bubble only when this node ignores.
    func handleMouseEvent(_ event: MouseEvent) {
        if consumeMouseEvent(event) { return }
        parent?.handleMouseEvent(event)
    }

    /// Called when the window clears `mouseCapture` without delivering `.ended`
    /// (dismiss-outside, retarget, subtree resign).
    func pointerCaptureEnded() {}

    /// Cancel an in-flight pointer gesture on this node.
    func pointerGestureCancelled() {}

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

    // MARK: - Selection (SwiftUI-shaped keyboard focus)

    /// Whether this element may become `Window.firstResponder`.
    ///
    /// Aligns with SwiftUI: **only text-entry controls** (TextField / SecureField /
    /// TextEditor) return `true`. Button, Toggle, Slider, Stepper, ScrollView,
    /// Menu chrome, etc. stay `false` — they use ``claimsPointerCapture`` for
    /// clicks, not keyboard focus. A focused control must show a soft caret
    /// (`cursorPosition` while first responder).
    var selectable: Bool { false }

    var canReceiveFocus: Bool { selectable && focusableFlag }

    var firstSelectableElement: Element? {
        if canReceiveFocus { return self }
        for control in children {
            if let element = control.firstSelectableElement { return element }
        }
        return nil
    }

    /// Click / drag owner that is not a text first-responder (Button, Slider, …).
    var claimsPointerCapture: Bool { false }

    /// When `true`, Application keeps `mouseCapture` after a left press so moves
    /// / release stay on this control (text drag, slider thumb).
    ///
    /// Press-activated Buttons leave this `false`: holding capture after the
    /// action stole clicks from a Menu that just opened under the cursor.
    var retainsPointerCaptureAfterPress: Bool { canReceiveFocus }

    /// `HStack` / `VStack` padding may hit the stack; donate the first selectable
    /// child (e.g. TextEditor). Root `ZStack` / overlay must leave this `false`.
    var donatesDescendantPointerOnClick: Bool { false }

    /// Pointer owner for a click that hit `self` (leaf Text, stack chrome, …).
    var pointerTargetOnClick: Element? {
        if claimsPointerCapture || canReceiveFocus { return self }
        // Outer `.padding` / stack / frame chrome may donate to a *focusable
        // editor* underneath (TextField border). It must NOT donate to a Button
        // that is merely wrapped by those modifiers — only hits inside the
        // Button's own subtree (label Text / inner padding) reach the Button
        // via the ancestor walk below.
        if donatesDescendantPointerOnClick,
           let target = firstSelectableElement,
           target.canReceiveFocus,
           !target.claimsPointerCapture
        {
            return target
        }
        var current = parent
        while let node = current {
            if node.claimsPointerCapture || node.canReceiveFocus { return node }
            current = node.parent
        }
        return nil
    }

    /// Keyboard focus target for the same click (`nil` if the pointer target
    /// is click-only, e.g. a menu trigger that is not selectable).
    var focusTargetOnClick: Element? {
        guard let pointer = pointerTargetOnClick, pointer.canReceiveFocus else { return nil }
        return pointer
    }

    // MARK: - Scrolling

    func scroll(to position: Position) {
        parent?.scroll(to: position + layer.frame.position)
    }
}

