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
        node.control = TextEditorControl(text: $text, isEnabled: isEnabled)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextEditorControl
        control.text = $text
        control.isEnabledFlag = isEnabled
        control.syncFromBinding()
        control.layer.invalidate()
    }
}

@MainActor
private final class TextEditorControl: Control {
    var text: Binding<String>
    var isEnabledFlag: Bool

    private var cachedText: String
    private var cursorIndex: String.Index
    private var contentOffset: Extended = 0
    private var visualLines: [String] = []
    private var lineRanges: [Range<String.Index>] = []
    private var needsRebuild = true

    init(text: Binding<String>, isEnabled: Bool) {
        self.text = text
        self.isEnabledFlag = isEnabled
        self.cachedText = text.wrappedValue
        self.cursorIndex = cachedText.endIndex
    }

    func syncFromBinding() {
        let newText = text.wrappedValue
        if newText != cachedText {
            let distance = cachedText.distance(from: cachedText.startIndex, to: min(cursorIndex, cachedText.endIndex))
            cachedText = newText
            cursorIndex = cachedText.index(
                cachedText.startIndex,
                offsetBy: min(distance, cachedText.count),
                limitedBy: cachedText.endIndex
            ) ?? cachedText.endIndex
            needsRebuild = true
        }
    }

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
        if needsRebuild {
            buildVisualLines(width: size.width.intValue)
        }
    }

    private func buildVisualLines(width: Int) {
        visualLines.removeAll()
        lineRanges.removeAll()

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
    }

    private func getVisualPosition(for index: String.Index) -> (line: Int, col: Int) {
        for (i, range) in lineRanges.enumerated() {
            if range.contains(index) {
                let prefix = cachedText[range.lowerBound..<index]
                return (i, String(prefix).width)
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
                var cell = Cell(char: char)
                if !isEnabledFlag { cell.attributes.faint = true }
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                for w in 1..<cw {
                    buffer.setCell(Cell(char: "\u{0000}"), at: Position(column: Extended(x + w), line: Extended(y)))
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

    private func commitText() {
        text.wrappedValue = cachedText
        layer.invalidate()
    }

    override var cursorPosition: Position? {
        guard isFirstResponder, isEnabledFlag else { return nil }
        let pos = getVisualPosition(for: cursorIndex)
        let visualY = pos.line - contentOffset.intValue
        if visualY >= 0 && visualY < layer.frame.size.height.intValue {
            return Position(column: Extended(pos.col), line: Extended(visualY))
        }
        return nil
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
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
            if cursorIndex > cachedText.startIndex {
                let prev = cachedText.index(before: cursorIndex)
                let distance = cachedText.distance(from: cachedText.startIndex, to: prev)
                cachedText.remove(at: prev)
                cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance)
                needsRebuild = true
                layout(size: layer.frame.size)
                scrollToKeepCursorVisible()
                commitText()
            }
        } else if char == "\n" || char == "\r" {
            let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
            cachedText.insert("\n", at: cursorIndex)
            cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance + 1)
            needsRebuild = true
            layout(size: layer.frame.size)
            scrollToKeepCursorVisible()
            commitText()
        } else {
            let distance = cachedText.distance(from: cachedText.startIndex, to: cursorIndex)
            cachedText.insert(char, at: cursorIndex)
            cursorIndex = cachedText.index(cachedText.startIndex, offsetBy: distance + 1)
            needsRebuild = true
            layout(size: layer.frame.size)
            scrollToKeepCursorVisible()
            commitText()
        }
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        guard isEnabledFlag else { return }
        if case .scroll(_, let deltaY) = event.type {
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
        } else if case .pressed(.left) = event.type {
            let local = event.position - absoluteFrame.position
            let visualY = local.line.intValue + contentOffset.intValue
            cursorIndex = getIndex(forVisualPosition: visualY, col: local.column.intValue)
            scrollToKeepCursorVisible()
            layer.invalidate()
        } else {
            super.handleMouseEvent(event)
        }
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
