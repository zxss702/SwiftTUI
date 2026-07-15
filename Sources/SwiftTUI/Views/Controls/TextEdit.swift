import Foundation

// MARK: - TextEditorStyle

/// 对齐 SwiftUI.TextEditorStyle（macOS 现行：automatic / plain / roundedBorder）。
@MainActor public protocol TextEditorStyle {}

@MainActor public struct AutomaticTextEditorStyle: TextEditorStyle {
    public init() {}
}

@MainActor public struct PlainTextEditorStyle: TextEditorStyle {
    public init() {}
}

@MainActor public struct RoundedBorderTextEditorStyle: TextEditorStyle {
    public init() {}
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
    public static var automatic: AutomaticTextEditorStyle { AutomaticTextEditorStyle() }
}

extension TextEditorStyle where Self == PlainTextEditorStyle {
    public static var plain: PlainTextEditorStyle { PlainTextEditorStyle() }
}

extension TextEditorStyle where Self == RoundedBorderTextEditorStyle {
    public static var roundedBorder: RoundedBorderTextEditorStyle { RoundedBorderTextEditorStyle() }
}

enum TextEditorStyleKind: Equatable {
    case automatic
    case plain
    case roundedBorder
}

@MainActor
protocol _TextEditorStyleResolvable {
    var textEditorStyleKind: TextEditorStyleKind { get }
}

extension AutomaticTextEditorStyle: _TextEditorStyleResolvable {
    var textEditorStyleKind: TextEditorStyleKind { .automatic }
}

extension PlainTextEditorStyle: _TextEditorStyleResolvable {
    var textEditorStyleKind: TextEditorStyleKind { .plain }
}

extension RoundedBorderTextEditorStyle: _TextEditorStyleResolvable {
    var textEditorStyleKind: TextEditorStyleKind { .roundedBorder }
}

private struct TextEditorStyleKindEnvironmentKey: EnvironmentKey {
    static var defaultValue: TextEditorStyleKind { .automatic }
}

extension EnvironmentValues {
    var textEditorStyleKind: TextEditorStyleKind {
        get { self[TextEditorStyleKindEnvironmentKey.self] }
        set { self[TextEditorStyleKindEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func textEditorStyle<S: TextEditorStyle>(_ style: S) -> some View {
        let kind = (style as? any _TextEditorStyleResolvable)?.textEditorStyleKind ?? .automatic
        return environment(\.textEditorStyleKind, kind)
    }
}

// MARK: - TextEditor

/// 多行可滚动文本编辑，对齐 SwiftUI.TextEditor。
@MainActor
public struct TextEditor: View {
    @Binding var text: String
    @Environment(\.textEditorStyleKind) private var styleKind
    @Environment(\.isEnabled) private var isEnabled

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        let core = TextEditorCore(text: $text, isEnabled: isEnabled)
        switch styleKind {
        case .roundedBorder:
            // macOS roundedBorder：圆角边框
            core.border(style: .rounded)
        case .automatic, .plain:
            core
        }
    }
}

/// 旧名；请优先使用 `TextEditor`。
public typealias TextEdit = TextEditor

// MARK: - Core

@MainActor
private struct TextEditorCore: View, PrimitiveView {
    @Binding var text: String
    var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.element = TextEditorElement(text: $text, isEnabled: isEnabled)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! TextEditorElement
        control.text = $text
        control.isEnabledFlag = isEnabled
        // External Binding changes only: local edits already rebuilt + invalidated.
        if control.syncFromBinding() {
            control.ensureVisualLines()
            control.layer.invalidate()
        }
    }
}

@MainActor
private final class TextEditorElement: Element {
    var text: Binding<String>
    var isEnabledFlag: Bool

    private var cachedText: String
    private var cursorIndex: String.Index
    private var contentOffset: Extended = 0
    private var visualLines: [String] = []
    private var lineRanges: [Range<String.Index>] = []
    private var needsRebuild = true
    private var lastBuiltWidth: Int = -1
    private var bindingDirty = false

    // MARK: - Selection / undo state

    /// Selection anchor; the head is `cursorIndex`.
    private var selectionAnchor: String.Index?
    /// Press location recorded on `.began`; becomes the anchor once a drag moves.
    private var pendingSelectionOrigin: String.Index?

    private struct UndoSnapshot {
        var text: String
        var cursorOffset: Int
    }

    /// Consecutive edits of the same group coalesce into one undo step.
    private enum EditGroup {
        case typing
        case deleting
    }

    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private var lastEditGroup: EditGroup?
    /// Last character inserted while the `.typing` group is open (undo
    /// word-boundary detection).
    private var lastInsertedCharacter: Character?
    private static let undoStackLimit = 100

    /// Selected range (half-open), or `nil` when the selection is empty.
    private var selectionRange: Range<String.Index>? {
        guard let anchor = selectionAnchor, anchor != cursorIndex else { return nil }
        return min(anchor, cursorIndex) ..< max(anchor, cursorIndex)
    }

    /// Collapse the selection without repainting (call sites invalidate).
    private func collapseSelection() {
        pendingSelectionOrigin = nil
        guard selectionAnchor != nil else { return }
        selectionAnchor = nil
        window?.selectionCoordinator.end(self)
    }

    private func markSelectionActive() {
        if selectionRange != nil {
            window?.selectionCoordinator.begin(self)
        }
    }

    /// Deletes the selected range (no undo recording — callers record).
    /// Returns `true` when a selection was removed.
    @discardableResult
    private func removeSelectedText() -> Bool {
        guard let range = selectionRange else { return false }
        let distance = cachedText.distance(from: cachedText.startIndex, to: range.lowerBound)
        cachedText.removeSubrange(range)
        cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance)
        collapseSelection()
        return true
    }

    private func cutSelection() {
        guard selectionRange != nil else { return }
        if let text = selectedText() {
            Clipboard.copy(text, vtRenderer: layer.rootRenderer?.vtRenderer)
        }
        applyTextMutation(undoGroup: nil) {
            removeSelectedText()
        }
    }

    // MARK: - Undo / redo

    /// Push an undo snapshot unless it coalesces with the previous edit group.
    /// Pass `nil` to force a snapshot (selection replace, cut, newline, tab, …);
    /// `force` breaks coalescing within a group (word/CJK boundaries).
    private func recordUndo(group: EditGroup?, force: Bool = false) {
        redoStack.removeAll()
        if force || group == nil || group != lastEditGroup {
            let offset = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
            undoStack.append(UndoSnapshot(text: cachedText, cursorOffset: offset))
            if undoStack.count > Self.undoStackLimit {
                undoStack.removeFirst()
            }
        }
        lastEditGroup = group
    }

    /// Whether inserting `char` starts a new undo step: CJK/emoji always do
    /// (character granularity); Latin text breaks at word starts (previous
    /// char was a space) and when switching back from wide characters.
    private func typingUndoBoundary(for char: Character) -> Bool {
        if char.undoesPerCharacter { return true }
        guard let last = lastInsertedCharacter else { return false }
        return last.undoesPerCharacter || (last == " " && char != " ")
    }

    private func performUndo() {
        guard let snapshot = undoStack.popLast() else { return }
        let offset = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
        redoStack.append(UndoSnapshot(text: cachedText, cursorOffset: offset))
        restore(snapshot)
    }

    private func performRedo() {
        guard let snapshot = redoStack.popLast() else { return }
        let offset = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
        undoStack.append(UndoSnapshot(text: cachedText, cursorOffset: offset))
        restore(snapshot)
    }

    private func restore(_ snapshot: UndoSnapshot) {
        cachedText = snapshot.text
        cursorIndex = cachedText.index(
            cachedText.startIndex,
            offsetBy: min(snapshot.cursorOffset, cachedText.count)
        )
        collapseSelection()
        lastEditGroup = nil
        needsRebuild = true
        ensureVisualLines()
        scrollToKeepCursorVisible()
        bindingDirty = true
        layer.invalidate()
        layer.rootRenderer?.application?.noteEditorNeedsCommit(self)
    }

    init(text: Binding<String>, isEnabled: Bool) {
        self.text = text
        self.isEnabledFlag = isEnabled
        self.cachedText = text.wrappedValue
        self.cursorIndex = cachedText.endIndex
    }

    override var needsBindingCommit: Bool { bindingDirty }

    override func commitBindingIfNeeded() {
        guard bindingDirty else { return }
        bindingDirty = false
        // Real Binding write: dependents (`frame(maxHeight:)`, `onChange`, …)
        // must see the new value and re-evaluate their body.
        text.wrappedValue = cachedText
    }

    /// Returns true when cached text was replaced from an external Binding write.
    @discardableResult
    func syncFromBinding() -> Bool {
        if bindingDirty { return false }
        let newText = text.wrappedValue
        guard newText != cachedText else { return false }
        let distance = cachedText.distance(from: cachedText.startIndex, to: min(cursorIndex, cachedText.endIndex))
        // Old-string indices must never survive onto the new string.
        selectionAnchor = nil
        pendingSelectionOrigin = nil
        cachedText = newText
        cursorIndex = cachedText.index(
            cachedText.startIndex,
            offsetBy: min(distance, cachedText.count),
            limitedBy: cachedText.endIndex
        ) ?? cachedText.endIndex
        needsRebuild = true
        return true
    }

    /// Text entry — the only controls that take keyboard first-responder focus.
    override var selectable: Bool { isEnabledFlag }

    override func size(proposedSize: Size) -> Size {
        if proposedSize.width != .infinity, proposedSize.height != .infinity {
            return Size(
                width: max(proposedSize.width, 1),
                height: max(proposedSize.height, 1)
            )
        }
        let w = proposedSize.width == .infinity ? Extended(40) : max(proposedSize.width, 1)
        let h = proposedSize.height == .infinity ? Extended(5) : max(proposedSize.height, 1)
        return Size(width: w, height: h)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        ensureVisualLines(width: size.width.intValue)
    }

    func ensureVisualLines(width: Int? = nil) {
        let width = width ?? max(layer.frame.size.width.intValue, 1)
        if needsRebuild || width != lastBuiltWidth {
            buildVisualLines(width: width)
        }
    }

    private func buildVisualLines(width: Int) {
        visualLines.removeAll(keepingCapacity: true)
        lineRanges.removeAll(keepingCapacity: true)

        var currentIndex = cachedText.startIndex
        var currentVisualLine = ""
        var currentVisualLineStart = currentIndex
        var currentWidth = 0

        while currentIndex < cachedText.endIndex {
            let char = cachedText[currentIndex]
            let charWidth = char.width

            if char == "\n" {
                let nextIndex = cachedText.index(after: currentIndex)
                visualLines.append(currentVisualLine)
                lineRanges.append(currentVisualLineStart ..< nextIndex)
                currentIndex = nextIndex
                currentVisualLine = ""
                currentVisualLineStart = currentIndex
                currentWidth = 0
                continue
            }

            if width > 0 && currentWidth + charWidth > width {
                visualLines.append(currentVisualLine)
                lineRanges.append(currentVisualLineStart ..< currentIndex)
                currentVisualLine = ""
                currentVisualLineStart = currentIndex
                currentWidth = 0
            }

            currentVisualLine.append(char)
            currentWidth += charWidth
            currentIndex = cachedText.index(after: currentIndex)
        }

        visualLines.append(currentVisualLine)
        lineRanges.append(currentVisualLineStart ..< currentIndex)
        needsRebuild = false
        lastBuiltWidth = width
    }

    private func getVisualPosition(for index: String.Index) -> (line: Int, col: Int) {
        for (i, range) in lineRanges.enumerated() {
            if range.contains(index) {
                var col = 0
                var idx = range.lowerBound
                while idx < index {
                    col += cachedText[idx].width
                    idx = cachedText.index(after: idx)
                }
                return (i, col)
            }
        }
        if let last = lineRanges.last, index == last.upperBound {
            return (lineRanges.count - 1, visualLines.last?.width ?? 0)
        }
        return (0, 0)
    }

    private func getIndex(forVisualPosition line: Int, col: Int) -> String.Index {
        guard line >= 0 && line < visualLines.count else { return cachedText.endIndex }
        let range = lineRanges[line]

        var currentWidth = 0
        var idx = range.lowerBound
        while idx < range.upperBound {
            let char = cachedText[idx]
            if char == "\n" { break }
            let charWidth = char.width
            if currentWidth + charWidth > col { break }
            currentWidth += charWidth
            idx = cachedText.index(after: idx)
        }
        return idx
    }

    override func draw(into buffer: inout ScreenBuffer) {
        ensureVisualLines()
        let height = layer.frame.size.height.intValue
        let width = layer.frame.size.width.intValue
        let startLine = contentOffset.intValue
        let endLine = min(visualLines.count, startLine + height)

        let selection = selectionRange

        for i in startLine..<endLine {
            let lineStr = visualLines[i]
            let y = i - startLine
            var x = 0
            var index = lineRanges[i].lowerBound
            for char in lineStr {
                let selected = selection?.contains(index) ?? false
                let cw = char.width
                if cw <= 0 {
                    // Tab / other ASCII controls report width 0; `1..<0` traps.
                    if char == "\t" {
                        var cell = Cell(char: " ")
                        if selected {
                            cell.backgroundColor = TextSelectionStyle.background
                        }
                        buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                        x += 1
                    }
                    index = cachedText.index(after: index)
                    continue
                }
                var cell = Cell(char: char)
                if !isEnabledFlag { cell.attributes.faint = true }
                if selected {
                    cell.backgroundColor = TextSelectionStyle.background
                    cell.foregroundColor = TextSelectionStyle.foreground
                }
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                if cw > 1 {
                    for w in 1..<cw {
                        var cont = Cell(char: "\u{0000}")
                        if selected {
                            cont.backgroundColor = TextSelectionStyle.background
                            cont.foregroundColor = TextSelectionStyle.foreground
                        }
                        buffer.setCell(cont, at: Position(column: Extended(x + w), line: Extended(y)))
                    }
                }
                x += cw
                index = cachedText.index(after: index)
            }
            // A selected line break shows as one highlighted cell after the text.
            let newlineSelected: Bool = {
                guard let selection,
                      index < lineRanges[i].upperBound,
                      index < cachedText.endIndex,
                      cachedText[index] == "\n"
                else { return false }
                return selection.contains(index)
            }()
            var isFirstPadding = true
            while x < width {
                var cell = Cell(char: " ")
                if newlineSelected, isFirstPadding {
                    cell.backgroundColor = TextSelectionStyle.background
                }
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                isFirstPadding = false
                x += 1
            }
        }

        for i in (endLine - startLine)..<height {
            for x in 0..<width {
                buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: Extended(i)))
            }
        }
    }

    private func scrollToKeepCursorVisible() {
        let pos = getVisualPosition(for: cursorIndex)
        let frameHeight = layer.frame.size.height.intValue
        if pos.line < contentOffset.intValue {
            contentOffset = Extended(pos.line)
        } else if pos.line >= contentOffset.intValue + frameHeight {
            contentOffset = Extended(pos.line - frameHeight + 1)
        }
    }

    private func applyTextMutation(
        undoGroup: EditGroup?,
        forceUndoSnapshot: Bool = false,
        _ mutate: () -> Void
    ) {
        recordUndo(group: undoGroup, force: forceUndoSnapshot)
        mutate()
        needsRebuild = true
        ensureVisualLines()
        scrollToKeepCursorVisible()
        bindingDirty = true
        layer.invalidate()
        layer.rootRenderer?.application?.noteEditorNeedsCommit(self)
    }

    override var cursorPosition: Position? {
        // The caret hides while a selection is active (macOS behavior).
        guard isFirstResponder, isEnabledFlag, selectionRange == nil else { return nil }
        ensureVisualLines()
        let pos = getVisualPosition(for: cursorIndex)
        let visualY = pos.line - contentOffset.intValue
        if visualY >= 0 && visualY < layer.frame.size.height.intValue {
            return Position(column: Extended(pos.col), line: Extended(visualY))
        }
        return nil
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
        ensureVisualLines()
        if event.isControl("x", raw: "\u{18}") {
            cutSelection()
            return
        }
        if event.isControl("z", raw: "\u{1a}") {
            performUndo()
            return
        }
        if event.isControl("y", raw: "\u{19}") {
            performRedo()
            return
        }
        if event.character == nil {
            let keycode = event.keycode
            let pos = getVisualPosition(for: cursorIndex)
            let shift = event.modifiers.contains(.shift)
            lastEditGroup = nil

            if shift, selectionAnchor == nil {
                selectionAnchor = cursorIndex
            }

            if !shift, let range = selectionRange {
                // Plain arrows collapse the selection to one end.
                if keycode == VTKeyCode.left || keycode == VTKeyCode.up {
                    cursorIndex = range.lowerBound
                } else if keycode == VTKeyCode.right || keycode == VTKeyCode.down {
                    cursorIndex = range.upperBound
                }
                collapseSelection()
                scrollToKeepCursorVisible()
                layer.invalidate()
                return
            }

            if keycode == VTKeyCode.left {
                if cursorIndex > cachedText.startIndex {
                    cursorIndex = cachedText.index(before: cursorIndex)
                }
            } else if keycode == VTKeyCode.right {
                if cursorIndex < cachedText.endIndex {
                    cursorIndex = cachedText.index(after: cursorIndex)
                }
            } else if keycode == VTKeyCode.up {
                if pos.line > 0 {
                    cursorIndex = getIndex(forVisualPosition: pos.line - 1, col: pos.col)
                } else {
                    cursorIndex = cachedText.startIndex
                }
            } else if keycode == VTKeyCode.down {
                if pos.line < visualLines.count - 1 {
                    cursorIndex = getIndex(forVisualPosition: pos.line + 1, col: pos.col)
                } else {
                    cursorIndex = cachedText.endIndex
                }
            }
            if shift {
                if selectionAnchor == cursorIndex {
                    collapseSelection()
                } else {
                    markSelectionActive()
                }
            } else {
                collapseSelection()
            }
            scrollToKeepCursorVisible()
            layer.invalidate()
            return
        }

        guard let char = event.character else { return }
        if char == "\u{03}" { return }

        if char == "\u{7F}" {
            if selectionRange != nil {
                applyTextMutation(undoGroup: nil) {
                    removeSelectedText()
                }
                return
            }
            guard cursorIndex > cachedText.startIndex else { return }
            applyTextMutation(undoGroup: .deleting) {
                let prev = cachedText.index(before: cursorIndex)
                let distance = cachedText.distance(from: cachedText.startIndex, to: prev)
                cachedText.remove(at: prev)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance)
            }
        } else if char == "\n" || char == "\r" {
            applyTextMutation(undoGroup: nil) {
                removeSelectedText()
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert("\n", at: cursorIndex)
                cursorIndex = cachedText.index(
                    cachedText.startIndex,
                    offsetBy: min(distance + 1, cachedText.count)
                )
            }
        } else if char == "\t" {
            // Tab has Character.width == 0; inserting it crashes wide-char padding in draw.
            let spaces = "    "
            applyTextMutation(undoGroup: nil) {
                removeSelectedText()
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert(contentsOf: spaces, at: cursorIndex)
                cursorIndex = cachedText.index(
                    cachedText.startIndex,
                    offsetBy: min(distance + spaces.count, cachedText.count)
                )
            }
        } else if char.isASCII && char.isWhitespace && char != " " {
            return
        } else if let ascii = char.asciiValue, ascii < 0x20 {
            return
        } else if char.width == 0, char.isASCII {
            return
        } else {
            let hadSelection = selectionRange != nil
            applyTextMutation(
                undoGroup: hadSelection ? nil : .typing,
                forceUndoSnapshot: !hadSelection && typingUndoBoundary(for: char)
            ) {
                removeSelectedText()
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert(char, at: cursorIndex)
                // ZWJ / VS16 may merge into the previous grapheme; clamp so
                // `offsetBy` never traps past `endIndex`.
                cursorIndex = cachedText.index(
                    cachedText.startIndex,
                    offsetBy: min(distance + 1, cachedText.count)
                )
            }
            lastInsertedCharacter = char
        }
    }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        guard isEnabledFlag, event.button == .left else { return false }
        ensureVisualLines()
        switch event.phase {
        case .began:
            if selectionAnchor != nil { collapseSelection() }
            placeCursor(at: event.position)
            pendingSelectionOrigin = cursorIndex
            lastEditGroup = nil
            window?.mouseCapture = self
            layer.invalidate()
            return true
        case .moved:
            placeCursor(at: event.position)
            if selectionAnchor == nil, let origin = pendingSelectionOrigin, origin != cursorIndex {
                selectionAnchor = origin
            }
            markSelectionActive()
            layer.invalidate()
            return true
        case .ended:
            placeCursor(at: event.position)
            if selectionAnchor == cursorIndex { collapseSelection() }
            pendingSelectionOrigin = nil
            if window?.mouseCapture === self {
                window?.mouseCapture = nil
            }
            layer.invalidate()
            return true
        case .cancelled:
            pendingSelectionOrigin = nil
            if window?.mouseCapture === self {
                window?.mouseCapture = nil
            }
            return true
        }
    }

    override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
        guard isEnabledFlag else { return false }
        ensureVisualLines()
        switch event.type {
        case .scroll(_, let deltaY):
            let maxOffset = max(0, visualLines.count - layer.frame.size.height.intValue)
            contentOffset += Extended(deltaY)
            if contentOffset.intValue < 0 { contentOffset = 0 }
            if contentOffset.intValue > maxOffset { contentOffset = Extended(maxOffset) }

            // Keep the caret visible while wheel-scrolling — but not when a
            // selection is active (the caret is the selection head and moving
            // it would silently change the selection).
            if selectionRange == nil {
                let pos = getVisualPosition(for: cursorIndex)
                let frameHeight = layer.frame.size.height.intValue
                if pos.line < contentOffset.intValue {
                    cursorIndex = getIndex(forVisualPosition: contentOffset.intValue, col: pos.col)
                } else if pos.line >= contentOffset.intValue + frameHeight {
                    cursorIndex = getIndex(forVisualPosition: contentOffset.intValue + frameHeight - 1, col: pos.col)
                }
            }
            layer.invalidate()
            return true
        default:
            return false
        }
    }

    private func placeCursor(at absolutePosition: Position) {
        let local = absolutePosition - absoluteFrame.position
        // Clamp so dragging above/below the viewport keeps selecting line by
        // line instead of jumping to endIndex.
        let visualY = min(
            max(0, local.line.intValue + contentOffset.intValue),
            max(0, visualLines.count - 1)
        )
        cursorIndex = getIndex(forVisualPosition: visualY, col: max(0, local.column.intValue))
        scrollToKeepCursorVisible()
    }

    override func becomeFirstResponder() {
        super.becomeFirstResponder()
        layer.invalidate()
    }

    override func resignFirstResponder() {
        super.resignFirstResponder()
        collapseSelection()
        layer.invalidate()
    }

    override func willRemoveFromParent() {
        window?.selectionCoordinator.end(self)
        super.willRemoveFromParent()
    }
}

// MARK: - SelectionOwner

extension TextEditorElement: SelectionOwner {
    func clearSelection() {
        guard selectionAnchor != nil else {
            pendingSelectionOrigin = nil
            return
        }
        collapseSelection()
        layer.invalidate()
    }

    func selectedText() -> String? {
        guard let range = selectionRange else { return nil }
        return String(cachedText[range])
    }
}
