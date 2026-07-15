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
        // #region agent log
        DebugSessionLog.write(
            hypothesisId: "TE1",
            location: "TextEditorElement.commitBindingIfNeeded",
            message: "binding committed",
            data: ["len": cachedText.count],
            runId: "post-cleanup"
        )
        // #endregion
    }

    /// Returns true when cached text was replaced from an external Binding write.
    @discardableResult
    func syncFromBinding() -> Bool {
        if bindingDirty { return false }
        let newText = text.wrappedValue
        guard newText != cachedText else { return false }
        // #region agent log
        DebugSessionLog.write(
            hypothesisId: "TE2",
            location: "TextEditorElement.syncFromBinding",
            message: "cache overwritten from Binding",
            data: [
                "wasLen": cachedText.count,
                "newLen": newText.count,
                "isFR": isFirstResponder,
            ],
            runId: "post-cleanup"
        )
        // #endregion
        let distance = cachedText.distance(from: cachedText.startIndex, to: min(cursorIndex, cachedText.endIndex))
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

        for i in startLine..<endLine {
            let lineStr = visualLines[i]
            let y = i - startLine
            var x = 0
            for char in lineStr {
                let cw = char.width
                if cw <= 0 {
                    // Tab / other ASCII controls report width 0; `1..<0` traps.
                    if char == "\t" {
                        buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: Extended(y)))
                        x += 1
                    }
                    continue
                }
                var cell = Cell(char: char)
                if !isEnabledFlag { cell.attributes.faint = true }
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                if cw > 1 {
                    for w in 1..<cw {
                        buffer.setCell(Cell(char: "\u{0000}"), at: Position(column: Extended(x + w), line: Extended(y)))
                    }
                }
                x += cw
            }
            while x < width {
                buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: Extended(y)))
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

    private func applyTextMutation(_ mutate: () -> Void) {
        mutate()
        needsRebuild = true
        ensureVisualLines()
        scrollToKeepCursorVisible()
        bindingDirty = true
        layer.invalidate()
        layer.rootRenderer?.application?.noteEditorNeedsCommit(self)
    }

    override var cursorPosition: Position? {
        guard isFirstResponder, isEnabledFlag else { return nil }
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
        if event.character == nil {
            let keycode = event.keycode
            let pos = getVisualPosition(for: cursorIndex)

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
            scrollToKeepCursorVisible()
            layer.invalidate()
            return
        }

        guard let char = event.character else { return }
        if char == "\u{03}" { return }

        if char == "\u{7F}" {
            guard cursorIndex > cachedText.startIndex else { return }
            applyTextMutation {
                let prev = cachedText.index(before: cursorIndex)
                let distance = cachedText.distance(from: cachedText.startIndex, to: prev)
                cachedText.remove(at: prev)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance)
            }
        } else if char == "\n" || char == "\r" {
            applyTextMutation {
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert("\n", at: cursorIndex)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance + 1)
            }
        } else if char == "\t" {
            // Tab has Character.width == 0; inserting it crashes wide-char padding in draw.
            let spaces = "    "
            applyTextMutation {
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert(contentsOf: spaces, at: cursorIndex)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance + spaces.count)
            }
        } else if char.isASCII && char.isWhitespace {
            return
        } else if char.width == 0 {
            return
        } else {
            applyTextMutation {
                let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
                cachedText.insert(char, at: cursorIndex)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance + 1)
            }
        }
    }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        guard isEnabledFlag, event.button == .left else { return false }
        ensureVisualLines()
        switch event.phase {
        case .began, .moved, .ended:
            placeCursor(at: event.position)
            if event.phase == .began {
                window?.mouseCapture = self
            }
            if event.phase == .ended, window?.mouseCapture === self {
                window?.mouseCapture = nil
            }
            layer.invalidate()
            return true
        case .cancelled:
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

            let pos = getVisualPosition(for: cursorIndex)
            let frameHeight = layer.frame.size.height.intValue
            if pos.line < contentOffset.intValue {
                cursorIndex = getIndex(forVisualPosition: contentOffset.intValue, col: pos.col)
            } else if pos.line >= contentOffset.intValue + frameHeight {
                cursorIndex = getIndex(forVisualPosition: contentOffset.intValue + frameHeight - 1, col: pos.col)
            }
            layer.invalidate()
            return true
        default:
            return false
        }
    }

    private func placeCursor(at absolutePosition: Position) {
        let local = absolutePosition - absoluteFrame.position
        let visualY = local.line.intValue + contentOffset.intValue
        cursorIndex = getIndex(forVisualPosition: visualY, col: local.column.intValue)
        scrollToKeepCursorVisible()
    }

    override func becomeFirstResponder() {
        super.becomeFirstResponder()
        layer.invalidate()
    }

    override func resignFirstResponder() {
        super.resignFirstResponder()
        layer.invalidate()
    }
}
