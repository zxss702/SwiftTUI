import Foundation

public extension View {
    /// Makes the content mouse-selectable: dragging paints a macOS-style
    /// light-blue selection, releasing (or Ctrl+C) copies the selected text to
    /// the system clipboard.
    ///
    /// The highlight is not drawn by this view: the region publishes its
    /// geometry to the window's selection coordinator, and a single top-level
    /// pass re-styles the final frame buffer after the whole layer tree has
    /// drawn. This keeps the selection layer out of the views and guarantees
    /// pixel-exact alignment (including wide CJK/emoji characters).
    ///
    /// Clean clicks (press + release without movement) are forwarded to the
    /// inner controls, so buttons and tap gestures keep working. Scroll-wheel
    /// events are unaffected. When the content lives inside a `ScrollView`,
    /// dragging past the top/bottom edge auto-scrolls while extending the
    /// selection. Any later click anywhere in the UI cancels the selection.
    func selectable() -> some View {
        SelectableModifier(content: self)
    }
}

@MainActor
private struct SelectableModifier<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
    }

    func passElement(_ control: Element, node: Node) -> Element {
        if let existing = control.parent?.parent as? SelectableElement,
           control.parent === existing.contentHost
        {
            return existing
        }
        let wrapper = SelectableElement()
        wrapper.mount(content: control)
        node.elements?.add(wrapper)
        return wrapper
    }
}

/// Gesture + state holder for a selectable region. Drawing is done globally:
/// see `SelectionCoordinator.applyHighlight`.
@MainActor
final class SelectableElement: Element {
    /// Plain container so content identity swaps don't disturb the wrapper.
    final class ContentHostElement: Element {
        override func size(proposedSize: Size) -> Size {
            children.first?.size(proposedSize: proposedSize) ?? .zero
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children.first?.layout(size: size)
        }
    }

    private(set) var contentHost = ContentHostElement()

    /// Selection endpoints in element-local coordinates (stable across
    /// ScrollView movement). `anchor` is where the drag started, `head`
    /// follows the pointer. Both endpoints are inclusive.
    private(set) var selectionAnchor: Position?
    private(set) var selectionHead: Position?
    private var isSelecting = false
    private var pressPosition: Position?
    private var pressButton: MouseButton = .left

    /// Text captured per local row while it was visible during the drag
    /// (columns map 1:1 to cells; continuation cells stored as "\u{0000}").
    private var capturedRows: [Int: [Character?]] = [:]

    /// Edge auto-scroll while dragging beyond the visible viewport.
    private var autoScrollWorkID: HostClock.WorkID?
    private var lastDragPosition: Position?

    func mount(content: Element) {
        if children.isEmpty {
            addSubview(contentHost, at: 0)
        }
        contentHost.syncChild(content, at: 0)
    }

    var hasSelection: Bool { selectionAnchor != nil && selectionHead != nil }

    /// Normalized (start, end) in row-major order, both inclusive.
    var normalizedSelection: (start: Position, end: Position)? {
        guard let a = selectionAnchor, let h = selectionHead else { return nil }
        if (a.line, a.column) <= (h.line, h.column) { return (a, h) }
        return (h, a)
    }

    // MARK: - Layout

    override func size(proposedSize: Size) -> Size {
        contentHost.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        contentHost.layout(size: size)
    }

    // MARK: - Pointer gestures

    override var interceptsPointerGestures: Bool { true }
    override var retainsPointerCaptureAfterPress: Bool { true }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        switch event.phase {
        case .began:
            // A fresh press always drops any previous selection.
            if hasSelection { clearSelection() }
            pressPosition = event.position
            pressButton = event.button
            lastDragPosition = event.position
            isSelecting = false
            return true

        case .moved:
            guard let press = pressPosition else { return false }
            lastDragPosition = event.position
            if !isSelecting, event.position != press {
                isSelecting = true
                window?.selectionCoordinator.begin(self)
                selectionAnchor = clampToBounds(localPosition(of: press))
            }
            if isSelecting {
                selectionHead = clampToBounds(localPosition(of: event.position))
                updateAutoScroll(pointer: event.position)
                layer.invalidate()
            }
            return true

        case .ended:
            stopAutoScroll()
            defer {
                pressPosition = nil
                lastDragPosition = nil
                isSelecting = false
            }
            if isSelecting {
                // Capture may not have run yet if the frame loop hasn't painted
                // between the last move and this release — refresh from the
                // live back buffer before copying.
                refreshCaptureFromScreen()
                if let text = selectedText(), !text.isEmpty {
                    Clipboard.copy(text, vtRenderer: layer.rootRenderer?.vtRenderer)
                }
                // Selection stays visible until the next click anywhere.
                return true
            }
            // Clean click: replay press+release on the control underneath.
            forwardClick(pressAt: pressPosition ?? event.position, releaseAt: event.position)
            return true

        case .cancelled:
            stopAutoScroll()
            pressPosition = nil
            lastDragPosition = nil
            if isSelecting { clearSelection() }
            isSelecting = false
            return true
        }
    }

    /// Synthesizes began/ended on the inner pointer owner so taps, buttons and
    /// caret placement behave exactly as without `.selectable()`.
    private func forwardClick(pressAt: Position, releaseAt: Position) {
        guard let parent else { return }
        let inParent = pressAt - parent.absoluteFrame.position
        guard let target = pointerGestureTargetBypassingInterception(at: inParent),
              target !== self
        else { return }
        let began = target.pointerGesture(
            PointerGestureEvent(phase: .began, position: pressAt, button: pressButton)
        )
        if began {
            _ = target.pointerGesture(
                PointerGestureEvent(phase: .ended, position: releaseAt, button: pressButton)
            )
        }
    }

    // MARK: - Selection geometry

    private func localPosition(of absolute: Position) -> Position {
        absolute - absoluteFrame.position
    }

    private func clampToBounds(_ position: Position) -> Position {
        let width = max(1, layer.frame.size.width.intValue)
        let height = max(1, layer.frame.size.height.intValue)
        return Position(
            column: Extended(min(max(0, position.column.intValue), width - 1)),
            line: Extended(min(max(0, position.line.intValue), height - 1))
        )
    }

    // MARK: - Text extraction

    /// Pull currently-visible selected rows straight from the VT back buffer.
    /// Needed when copy runs before the next paint pass has called
    /// `captureVisibleRow` (fast drag-release), and as a freshness refresh
    /// for Ctrl+C.
    func refreshCaptureFromScreen() {
        guard let region = selectionHighlightRegion(),
              let vt = layer.rootRenderer?.vtRenderer
        else { return }
        let origin = region.frame.position
        let width = max(1, region.frame.size.width.intValue)
        let bufSize = vt.back.size

        for localRow in region.start.line.intValue ... region.end.line.intValue {
            var characters: [Character?] = []
            characters.reserveCapacity(width)
            var anyVisible = false
            for column in 0 ..< width {
                let row = origin.line.intValue + localRow + 1
                let col = origin.column.intValue + column + 1
                guard row >= 1, col >= 1,
                      row <= bufSize.heightInt, col <= bufSize.widthInt
                else {
                    characters.append(nil)
                    continue
                }
                let char = vt.back[VTPosition(row: row, column: col)].character
                characters.append(char)
                anyVisible = true
            }
            if anyVisible {
                captureVisibleRow(localRow, characters: characters)
            }
        }
    }

    func extractedSelectionText() -> String? {
        guard let region = selectionHighlightRegion() else { return nil }
        refreshCaptureFromScreen()
        var lines: [String] = []
        for row in region.start.line.intValue ... region.end.line.intValue {
            guard let columns = region.selectedColumns(inRow: row) else { continue }
            guard let cells = capturedRows[row] else {
                lines.append("")
                continue
            }
            var line = ""
            for column in columns where column < cells.count {
                // Skip `.selectionDisabled()` cells (line-number gutters).
                if region.isMasked(column: column, row: row) { continue }
                guard let char = cells[column], char != "\u{0000}" else { continue }
                line.append(char)
            }
            // Cells beyond the text content are drawn as spaces; trim them.
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(line)
        }
        while let last = lines.last, last.isEmpty, lines.count > 1 {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Edge auto-scroll

    /// Visible rectangle used for edge detection. Prefer the enclosing
    /// ScrollView viewport so a tall LazyVStack inside a short viewport still
    /// auto-scrolls when the pointer hits the top/bottom of the *screen*, not
    /// the distant ends of the full content frame.
    private var edgeScrollFrame: Rect {
        scrollViewportAbsoluteFrame ?? absoluteFrame
    }

    private func updateAutoScroll(pointer: Position) {
        let frame = edgeScrollFrame
        let above = pointer.line < frame.minLine
        let below = pointer.line > frame.maxLine
        guard above || below else {
            stopAutoScroll()
            return
        }
        guard autoScrollWorkID == nil,
              let clock = layer.rootRenderer?.application?.clock
        else { return }
        autoScrollWorkID = clock.scheduleRepeating(every: 0.05) { [weak self] in
            self?.autoScrollTick()
        }
    }

    private func autoScrollTick() {
        guard isSelecting, let pointer = lastDragPosition else {
            stopAutoScroll()
            return
        }
        let frame = edgeScrollFrame
        let target: Position
        if pointer.line < frame.minLine {
            let local = localPosition(of: Position(column: pointer.column, line: frame.minLine))
            target = Position(column: local.column, line: local.line - 1)
        } else if pointer.line > frame.maxLine {
            let local = localPosition(of: Position(column: pointer.column, line: frame.maxLine))
            target = Position(column: local.column, line: local.line + 1)
        } else {
            stopAutoScroll()
            return
        }
        // Bubbles to an enclosing ScrollView (no-op without one).
        scroll(to: target)
        selectionHead = clampToBounds(target)
        layer.invalidate()
        layer.rootRenderer?.application?.scheduleUpdate()
    }

    private func stopAutoScroll() {
        if let id = autoScrollWorkID {
            layer.rootRenderer?.application?.clock.cancel(id)
            autoScrollWorkID = nil
        }
    }

    override func willRemoveFromParent() {
        stopAutoScroll()
        window?.selectionCoordinator.end(self)
        super.willRemoveFromParent()
    }
}

extension SelectableElement: SelectionOwner {
    func clearSelection() {
        guard hasSelection else { return }
        selectionAnchor = nil
        selectionHead = nil
        capturedRows.removeAll(keepingCapacity: true)
        window?.selectionCoordinator.end(self)
        layer.invalidate()
    }

    func selectedText() -> String? {
        extractedSelectionText()
    }

    func selectionHighlightRegion() -> SelectionHighlightRegion? {
        guard let (start, end) = normalizedSelection else { return nil }
        return SelectionHighlightRegion(
            frame: absoluteFrame,
            start: start,
            end: end,
            maskedRects: collectMaskedRects()
        )
    }

    /// Region-local frames of `.selectionDisabled()` subtrees currently mounted
    /// under this region. Walked on demand: masked rows inside lazy containers
    /// mount/unmount with scrolling, so a cached list would go stale.
    private func collectMaskedRects() -> [Rect] {
        var rects: [Rect] = []
        let regionOrigin = absoluteFrame.position
        func walk(_ element: Element) {
            if let mask = element as? SelectionMaskElement, mask.isSelectionDisabled {
                let frame = mask.absoluteFrame
                rects.append(Rect(position: frame.position - regionOrigin, size: frame.size))
                return
            }
            for child in element.children {
                walk(child)
            }
        }
        walk(contentHost)
        return rects
    }

    /// Merge instead of replace: a partial redraw only sees part of the row,
    /// and must not wipe characters captured on earlier (fuller) frames.
    func captureVisibleRow(_ row: Int, characters: [Character?]) {
        guard var existing = capturedRows[row], existing.count == characters.count else {
            capturedRows[row] = characters
            return
        }
        for index in characters.indices where characters[index] != nil {
            existing[index] = characters[index]
        }
        capturedRows[row] = existing
    }
}
