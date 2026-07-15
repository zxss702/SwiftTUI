import Foundation

// MARK: - TextAlignment

public enum TextAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

public extension EnvironmentValues {
    var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

public extension View {
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}

// MARK: - onSubmit

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

private struct SubmitActionKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var submitAction: (() -> Void)? {
        get { self[SubmitActionKey.self] }
        set { self[SubmitActionKey.self] = newValue }
    }
}

public extension View {
    func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        _ = triggers
        return environment(\.submitAction, action)
    }
}

extension EnvironmentValues {
    public var placeholderColor: Color {
        get { self[PlaceholderColorEnvironmentKey.self] }
        set { self[PlaceholderColorEnvironmentKey.self] = newValue }
    }
}

private struct PlaceholderColorEnvironmentKey: EnvironmentKey {
    static var defaultValue: Color { .brightBlack }
}

@MainActor
private final class StringBox {
    var value = ""
}

// MARK: - TextField

/// SwiftUI 风格单行输入：`Binding`、对齐、定宽下行内随光标滚动。
@MainActor
public struct TextField: View {
    private let placeholder: String
    private let text: Binding<String>
    private let legacyAction: ((String) -> Void)?

    @Environment(\.textFieldStyleKind) private var styleKind

    public init(_ title: String, text: Binding<String>) {
        self.placeholder = title
        self.text = text
        self.legacyAction = nil
    }

    public init(text: Binding<String>, prompt: String? = nil) {
        self.placeholder = prompt ?? ""
        self.text = text
        self.legacyAction = nil
    }

    /// 旧 API：回车提交。
    public init(placeholder: String? = nil, action: @escaping (String) -> Void) {
        self.placeholder = placeholder ?? ""
        self.legacyAction = action
        let box = StringBox()
        self.text = Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }

    public var body: some View {
        let core = TextFieldCore(
            placeholder: placeholder,
            text: text,
            legacyAction: legacyAction,
            secure: false
        )
        switch styleKind {
        case .roundedBorder:
            core.border(style: .rounded)
        case .squareBorder:
            core.border(style: .default)
        case .automatic, .plain:
            core
        }
    }
}

@MainActor
private struct TextFieldCore: View, PrimitiveView {
    let placeholder: String
    let text: Binding<String>
    let legacyAction: ((String) -> Void)?
    let secure: Bool

    @Environment(\.placeholderColor) private var placeholderColor: Color
    @Environment(\.multilineTextAlignment) private var alignment: TextAlignment
    @Environment(\.submitAction) private var submitAction: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        let control = TextFieldElement(
            text: text,
            placeholder: placeholder,
            placeholderColor: placeholderColor,
            alignment: alignment,
            isEnabled: isEnabled,
            submitAction: submitAction,
            legacyAction: legacyAction
        )
        control.secure = secure
        node.element = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! TextFieldElement
        control.text = text
        control.placeholder = placeholder
        control.placeholderColor = placeholderColor
        control.alignment = alignment
        control.isEnabledFlag = isEnabled
        control.submitAction = submitAction
        control.legacyAction = legacyAction
        control.secure = secure
        if control.syncFromBinding() {
            control.layer.invalidate()
        }
    }
}

@MainActor
final class TextFieldElement: Element {
    var text: Binding<String>
    var placeholder: String
    var placeholderColor: Color
    var alignment: TextAlignment
    var isEnabledFlag: Bool
    var submitAction: (() -> Void)?
    var legacyAction: ((String) -> Void)?
    /// SecureField：绘制为 `•`
    var secure = false

    /// 安全模式：刚输入的字符短暂明文显示（下一次输入或约 1s 后变 `•`）。
    private var revealedSecureIndex: Int? = nil
    private var revealWorkID: HostClock.WorkID?

    /// 光标在字符串中的 Character 偏移。
    private var cursorIndex: Int = 0
    /// 可见窗口左侧列偏移。
    private var scrollOffset: Int = 0
    private var cachedText: String = ""
    /// Local buffer is authoritative until the next frame commits Binding.
    private var bindingDirty = false
    private var editGeneration: UInt64 = 0

    // MARK: - Selection / undo state

    /// Selection anchor (Character offset); the head is `cursorIndex`.
    private var selectionAnchor: Int?
    /// Press offset recorded on `.began`; becomes the anchor once a drag moves.
    private var pendingSelectionOrigin: Int?

    private struct UndoSnapshot {
        var text: String
        var cursor: Int
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

    /// Selected character range (half-open), or `nil` when the selection is empty.
    private var selectionRange: Range<Int>? {
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

    /// Deletes the selected characters (no undo recording — callers record).
    /// Returns `true` when a selection was removed.
    @discardableResult
    private func removeSelectedCharacters() -> Bool {
        guard let range = selectionRange else { return false }
        var chars = Array(cachedText)
        chars.removeSubrange(range)
        cachedText = String(chars)
        cursorIndex = range.lowerBound
        collapseSelection()
        return true
    }

    private func cutSelection() {
        guard selectionRange != nil else { return }
        if let text = selectedText() {
            Clipboard.copy(text, vtRenderer: layer.rootRenderer?.vtRenderer)
        }
        recordUndo(group: nil)
        removeSelectedCharacters()
        maskSecureImmediately()
        stageLocalEdit()
    }

    // MARK: - Undo / redo

    /// Push an undo snapshot unless it coalesces with the previous edit group.
    /// Pass `nil` to force a snapshot (selection replace, cut, tab, …);
    /// `force` breaks coalescing within a group (word/CJK boundaries).
    private func recordUndo(group: EditGroup?, force: Bool = false) {
        redoStack.removeAll()
        if force || group == nil || group != lastEditGroup {
            undoStack.append(UndoSnapshot(text: cachedText, cursor: cursorIndex))
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
        redoStack.append(UndoSnapshot(text: cachedText, cursor: cursorIndex))
        restore(snapshot)
    }

    private func performRedo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(UndoSnapshot(text: cachedText, cursor: cursorIndex))
        restore(snapshot)
    }

    private func restore(_ snapshot: UndoSnapshot) {
        cachedText = snapshot.text
        cursorIndex = min(snapshot.cursor, cachedText.count)
        collapseSelection()
        lastEditGroup = nil
        maskSecureImmediately()
        stageLocalEdit()
    }

    init(
        text: Binding<String>,
        placeholder: String,
        placeholderColor: Color,
        alignment: TextAlignment,
        isEnabled: Bool,
        submitAction: (() -> Void)?,
        legacyAction: ((String) -> Void)?
    ) {
        self.text = text
        self.placeholder = placeholder
        self.placeholderColor = placeholderColor
        self.alignment = alignment
        self.isEnabledFlag = isEnabled
        self.submitAction = submitAction
        self.legacyAction = legacyAction
        self.cachedText = text.wrappedValue
        self.cursorIndex = cachedText.count
    }

    override var needsBindingCommit: Bool { bindingDirty }

    override func commitBindingIfNeeded() {
        guard bindingDirty else { return }
        bindingDirty = false
        // Real Binding write: dependents must re-evaluate (onChange, derived layout).
        text.wrappedValue = cachedText
    }

    private func stageLocalEdit() {
        editGeneration &+= 1
        bindingDirty = true
        ensureCursorVisible()
        layer.invalidate()
        layer.rootRenderer?.application?.noteEditorNeedsCommit(self)
    }

    @discardableResult
    func syncFromBinding() -> Bool {
        // Local edits win until frame commit; ignore Binding that still lags.
        if bindingDirty { return false }
        let newText = text.wrappedValue
        guard newText != cachedText else { return false }
        cachedText = newText
        cursorIndex = min(cursorIndex, cachedText.count)
        collapseSelection()
        maskSecureImmediately()
        ensureCursorVisible()
        return true
    }

    /// Text entry — the only controls that take keyboard first-responder focus.
    override var selectable: Bool { isEnabledFlag }

    override func size(proposedSize: Size) -> Size {
        // 有限宽度时占满提案宽（单行输入默认拉满）。
        if proposedSize.width != .infinity, proposedSize.width > 0 {
            return Size(width: proposedSize.width, height: 1)
        }
        let content = max(cachedText.width, placeholder.width, 10)
        return Size(width: Extended(content), height: 1)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        ensureCursorVisible()
    }

    override func willRemoveFromParent() {
        cancelRevealTimer()
        window?.selectionCoordinator.end(self)
        super.willRemoveFromParent()
    }

    override func handleEvent(_ char: Character) {
        guard isEnabledFlag else { return }
        if char == "\n" {
            maskSecureImmediately()
            // Flush Binding before submit so handlers see final text.
            bindingDirty = false
            text.wrappedValue = cachedText
            submitAction?()
            legacyAction?(cachedText)
            if legacyAction != nil {
                cachedText = ""
                cursorIndex = 0
                scrollOffset = 0
                text.wrappedValue = ""
                layer.invalidate()
                layer.rootRenderer?.application?.requestPaint()
            }
            return
        }
        if char == ASCII.DEL || char == "\u{7f}" {
            if selectionRange != nil {
                recordUndo(group: nil)
                removeSelectedCharacters()
                maskSecureImmediately()
                stageLocalEdit()
                return
            }
            guard cursorIndex > 0 else { return }
            recordUndo(group: .deleting)
            var chars = Array(cachedText)
            chars.remove(at: cursorIndex - 1)
            cachedText = String(chars)
            cursorIndex -= 1
            maskSecureImmediately()
            stageLocalEdit()
            return
        }
        if char == "\t" {
            recordUndo(group: nil)
            removeSelectedCharacters()
            let spaces = Array("    ")
            var chars = Array(cachedText)
            chars.insert(contentsOf: spaces, at: cursorIndex)
            cachedText = String(chars)
            cursorIndex += spaces.count
            stageLocalEdit()
            return
        }
        if char.isASCII && char.isWhitespace && char != " " { return }
        if let ascii = char.asciiValue, ascii < 0x20 { return }
        if char.width == 0 { return }
        if selectionRange != nil {
            recordUndo(group: nil)
            removeSelectedCharacters()
        } else {
            recordUndo(group: .typing, force: typingUndoBoundary(for: char))
            collapseSelection()
        }
        lastInsertedCharacter = char
        var chars = Array(cachedText)
        chars.insert(char, at: cursorIndex)
        cachedText = String(chars)
        let insertedAt = cursorIndex
        cursorIndex += 1
        if secure {
            revealSecureCharacter(at: insertedAt)
        }
        stageLocalEdit()
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
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
        if event.keycode == VTKeyCode.left || event.keycode == VTKeyCode.right {
            let isLeft = event.keycode == VTKeyCode.left
            lastEditGroup = nil
            if event.modifiers.contains(.shift) {
                if selectionAnchor == nil { selectionAnchor = cursorIndex }
                if isLeft, cursorIndex > 0 { cursorIndex -= 1 }
                if !isLeft, cursorIndex < cachedText.count { cursorIndex += 1 }
                if selectionAnchor == cursorIndex {
                    collapseSelection()
                } else {
                    markSelectionActive()
                }
            } else if let range = selectionRange {
                cursorIndex = isLeft ? range.lowerBound : range.upperBound
                collapseSelection()
            } else {
                if isLeft, cursorIndex > 0 { cursorIndex -= 1 }
                if !isLeft, cursorIndex < cachedText.count { cursorIndex += 1 }
                collapseSelection()
            }
            maskSecureImmediately()
            ensureCursorVisible()
            layer.invalidate()
            return
        }
        super.handleKeyEvent(event)
    }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        guard isEnabledFlag, event.button == .left else { return false }
        let local = event.position - absoluteFrame.position
        let col = max(0, local.column.intValue)
        switch event.phase {
        case .began:
            if selectionAnchor != nil { collapseSelection() }
            cursorIndex = indexForVisibleColumn(col)
            pendingSelectionOrigin = cursorIndex
            lastEditGroup = nil
            maskSecureImmediately()
            ensureCursorVisible()
            layer.invalidate()
            return true
        case .moved:
            cursorIndex = indexForVisibleColumn(col)
            if selectionAnchor == nil, let origin = pendingSelectionOrigin, origin != cursorIndex {
                selectionAnchor = origin
            }
            markSelectionActive()
            ensureCursorVisible()
            layer.invalidate()
            return true
        case .ended:
            cursorIndex = indexForVisibleColumn(col)
            if selectionAnchor == cursorIndex { collapseSelection() }
            pendingSelectionOrigin = nil
            maskSecureImmediately()
            ensureCursorVisible()
            layer.invalidate()
            return true
        case .cancelled:
            pendingSelectionOrigin = nil
            return false
        }
    }

    override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
        false
    }

    override var cursorPosition: Position? {
        // The caret hides while a selection is active (macOS behavior).
        guard isFirstResponder, isEnabledFlag, selectionRange == nil else { return nil }
        let cursorCol = columnOffset(upTo: cursorIndex)
        let visible = cursorCol - scrollOffset
        let width = max(1, layer.frame.size.width.intValue)
        guard visible >= 0, visible < width else { return nil }
        return Position(column: Extended(visible), line: 0)
    }

    override func draw(into buffer: inout ScreenBuffer) {
        let width = max(1, layer.frame.size.width.intValue)
        // 先清行再画字。不能用 `cell(at:) == nil` 填空格：VT 路径下 cell(at:) 恒为 nil，
        // 会把刚写入的正文整行盖成空格（表现为有光标/有内容却看不到字）。
        for x in 0 ..< width {
            buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: 0))
        }

        let display: String
        let color: Color
        if cachedText.isEmpty {
            display = placeholder
            color = placeholderColor
        } else if secure {
            display = secureDisplayString()
            color = .default
        } else {
            display = cachedText
            color = .default
        }

        if cachedText.isEmpty {
            let totalWidth = display.width
            let startCol: Int
            switch alignment {
            case .leading: startCol = 0
            case .center: startCol = max(0, (width - totalWidth) / 2)
            case .trailing: startCol = max(0, width - totalWidth)
            }
            drawString(display, at: startCol, color: color, faint: true, into: &buffer, maxWidth: width)
        } else {
            ensureCursorVisible()
            let slice = visibleSlice(of: display, window: width)
            drawString(
                slice, at: 0, color: color, faint: false, into: &buffer, maxWidth: width,
                highlightColumns: selectedDisplayColumns, columnBase: scrollOffset
            )
        }
    }

    /// Selected range converted to absolute display columns (half-open).
    private var selectedDisplayColumns: Range<Int>? {
        guard let range = selectionRange else { return nil }
        let lower = columnOffset(upTo: range.lowerBound)
        let upper = columnOffset(upTo: range.upperBound)
        guard lower < upper else { return nil }
        return lower ..< upper
    }

    override func becomeFirstResponder() {
        super.becomeFirstResponder()
        layer.invalidate()
    }

    override func resignFirstResponder() {
        super.resignFirstResponder()
        collapseSelection()
        maskSecureImmediately()
        layer.invalidate()
    }

    // MARK: - Secure reveal

    private func secureDisplayString() -> String {
        var result = ""
        for (i, ch) in cachedText.enumerated() {
            if revealedSecureIndex == i {
                result.append(ch)
            } else {
                result.append("•")
            }
        }
        return result
    }

    private func revealSecureCharacter(at index: Int) {
        cancelRevealTimer()
        revealedSecureIndex = index
        guard let clock = layer.rootRenderer?.application?.clock else { return }
        revealWorkID = clock.schedule(after: 1.0) { [weak self] in
            guard let self else { return }
            self.revealedSecureIndex = nil
            self.revealWorkID = nil
            self.layer.invalidate()
            self.layer.rootRenderer?.application?.scheduleUpdate()
        }
    }

    private func maskSecureImmediately() {
        cancelRevealTimer()
        if revealedSecureIndex != nil {
            revealedSecureIndex = nil
        }
    }

    private func cancelRevealTimer() {
        if let id = revealWorkID {
            layer.rootRenderer?.application?.clock.cancel(id)
            revealWorkID = nil
        }
    }

    // MARK: - Scroll / columns

    /// 安全模式默认按 `•`（宽 1）；短暂明文的那一格用真实宽度。
    private func displayWidth(at index: Int, character: Character) -> Int {
        guard secure else { return character.width }
        if revealedSecureIndex == index {
            return character.width
        }
        return 1
    }

    private func columnOffset(upTo characterIndex: Int) -> Int {
        let chars = Array(cachedText)
        let end = min(characterIndex, chars.count)
        var total = 0
        for i in 0 ..< end {
            total += displayWidth(at: i, character: chars[i])
        }
        return total
    }

    private func ensureCursorVisible() {
        let width = max(1, layer.frame.size.width.intValue)
        let cursorCol = columnOffset(upTo: cursorIndex)
        if cursorCol < scrollOffset {
            scrollOffset = cursorCol
        } else if cursorCol >= scrollOffset + width {
            scrollOffset = cursorCol - width + 1
        }
        scrollOffset = max(0, scrollOffset)
    }

    private func visibleSlice(of string: String, window: Int) -> String {
        // `string` 已是最终显示串（含 • / 明文），按各字符真实显示宽切片。
        var col = 0
        var result = ""
        for ch in string {
            let w = ch.width
            let next = col + w
            if next <= scrollOffset {
                col = next
                continue
            }
            if col >= scrollOffset + window {
                break
            }
            result.append(ch)
            col = next
        }
        return result
    }

    private func indexForVisibleColumn(_ visibleColumn: Int) -> Int {
        let target = scrollOffset + visibleColumn
        var col = 0
        var index = 0
        for ch in cachedText {
            let w = displayWidth(at: index, character: ch)
            if col + w / 2 >= target { return index }
            col += w
            index += 1
            if col >= target { return index }
        }
        return cachedText.count
    }

    private func drawString(
        _ string: String,
        at startCol: Int,
        color: Color,
        faint: Bool,
        into buffer: inout ScreenBuffer,
        maxWidth: Int,
        highlightColumns: Range<Int>? = nil,
        columnBase: Int = 0
    ) {
        var currentWidth = startCol
        for ch in string {
            let selected = highlightColumns?.contains(columnBase + currentWidth) ?? false
            let charWidth = ch.width
            if charWidth <= 0 {
                if ch == "\t", currentWidth < maxWidth {
                    var cell = Cell(char: " ", foregroundColor: color)
                    cell.attributes.faint = faint
                    if selected {
                        cell.backgroundColor = TextSelectionStyle.background
                        cell.foregroundColor = TextSelectionStyle.foreground
                    }
                    buffer.setCell(cell, at: Position(column: Extended(currentWidth), line: 0))
                    currentWidth += 1
                }
                continue
            }
            if currentWidth >= maxWidth { break }
            if currentWidth + charWidth > maxWidth { break }
            var cell = Cell(char: ch, foregroundColor: color)
            cell.attributes.faint = faint
            if selected {
                cell.backgroundColor = TextSelectionStyle.background
                cell.foregroundColor = TextSelectionStyle.foreground
            }
            buffer.setCell(cell, at: Position(column: Extended(currentWidth), line: 0))
            if charWidth > 1 {
                for w in 1 ..< charWidth {
                    var cont = Cell(char: "\u{0000}", foregroundColor: color)
                    cont.attributes.faint = faint
                    if selected {
                        cont.backgroundColor = TextSelectionStyle.background
                        cont.foregroundColor = TextSelectionStyle.foreground
                    }
                    buffer.setCell(cont, at: Position(column: Extended(currentWidth + w), line: 0))
                }
            }
            currentWidth += charWidth
        }
    }
}

// MARK: - SelectionOwner

extension TextFieldElement: SelectionOwner {
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
        let chars = Array(cachedText)
        guard range.lowerBound >= 0, range.upperBound <= chars.count else { return nil }
        return String(chars[range])
    }
}
