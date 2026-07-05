import Foundation

@MainActor public struct TextEdit: View, PrimitiveView {
    @Binding public var text: String
    
    public init(text: Binding<String>) {
        self._text = text
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.control = TextEditControl(text: text) { newText in
            self.text = newText
        }
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextEditControl
        if control.text != text {
            control.text = text
        }
        control.action = { newText in
            self.text = newText
        }
    }
}

private class TextEditControl: Control {
    var text: String {
        didSet {
            if text != oldValue {
                needsLayout = true
                layer.invalidate()
            }
        }
    }
    var action: (String) -> Void
    
    init(text: String, action: @escaping (String) -> Void) {
        self.text = text
        self.action = action
        self.cursorIndex = text.endIndex
    }
    
    var cursorIndex: String.Index
    var contentOffset: Extended = 0
    
    private var visualLines: [String] = []
    private var lineRanges: [Range<String.Index>] = []
    private var needsLayout = true
    
    private func buildVisualLines(width: Int) {
        visualLines.removeAll()
        lineRanges.removeAll()
        
        var currentIndex = text.startIndex
        var currentVisualLine = ""
        var currentVisualLineStart = currentIndex
        var currentWidth = 0
        
        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            let charWidth = char.width
            
            if char == "\n" {
                let nextIndex = text.index(after: currentIndex)
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
            currentIndex = text.index(after: currentIndex)
        }
        
        // Append last line (even if empty, to allow cursor at the end)
        visualLines.append(currentVisualLine)
        lineRanges.append(currentVisualLineStart ..< currentIndex)
        
        needsLayout = false
    }
    
    private func getVisualPosition(for index: String.Index) -> (line: Int, col: Int) {
        for (i, range) in lineRanges.enumerated() {
            if range.contains(index) {
                let prefix = text[range.lowerBound..<index]
                // Note: prefix should not contain \n because if index was at \n, it's not in the prefix.
                // Wait, if index IS the \n, the prefix string does not contain the \n.
                // width of prefix is the col.
                return (i, String(prefix).width)
            }
        }
        // If at the very end
        if let last = lineRanges.last, index == last.upperBound {
            return (lineRanges.count - 1, visualLines.last?.width ?? 0)
        }
        return (0, 0)
    }
    
    private func getIndex(forVisualPosition line: Int, col: Int) -> String.Index {
        guard line >= 0 && line < visualLines.count else { return text.endIndex }
        let range = lineRanges[line]
        
        var currentWidth = 0
        var idx = range.lowerBound
        while idx < range.upperBound {
            let char = text[idx]
            if char == "\n" { break }
            let charWidth = char.width
            if currentWidth + charWidth > col {
                break
            }
            currentWidth += charWidth
            idx = text.index(after: idx)
        }
        return idx
    }
    
    override func layout(size: Size) {
        super.layout(size: size)
        if needsLayout {
            buildVisualLines(width: size.width.intValue)
        }
    }
    
    override func draw(into buffer: inout ScreenBuffer) {
        let frame = layer.frame
        let height = frame.size.height.intValue
        
        let startLine = contentOffset.intValue
        let endLine = min(visualLines.count, startLine + height)
        
        for i in startLine..<endLine {
            let lineStr = visualLines[i]
            let y = i - startLine
            var x = 0
            for char in lineStr {
                let cw = char.width
                buffer.setCell(Cell(char: char), at: Position(column: Extended(x), line: Extended(y)))
                for w in 1..<cw {
                    buffer.setCell(Cell(char: "\u{0000}"), at: Position(column: Extended(x + w), line: Extended(y)))
                }
                x += cw
            }
            while x < layer.frame.size.width.intValue {
                buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: Extended(y)))
                x += 1
            }
        }
        
        for i in (endLine - startLine)..<layer.frame.size.height.intValue {
            for x in 0..<layer.frame.size.width.intValue {
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
    
    override var selectable: Bool { true }
    
    override var cursorPosition: Position? {
        guard isFirstResponder else { return nil }
        let pos = getVisualPosition(for: cursorIndex)
        let visualY = pos.line - contentOffset.intValue
        if visualY >= 0 && visualY < layer.frame.size.height.intValue {
            return Position(column: Extended(pos.col), line: Extended(visualY))
        }
        return nil
    }
    
    override func handleKeyEvent(_ event: KeyEvent) {
        if event.character == nil {
            let keycode = event.keycode
            let pos = getVisualPosition(for: cursorIndex)
            
            if keycode == VTKeyCode.left {
                if cursorIndex > text.startIndex {
                    cursorIndex = text.index(before: cursorIndex)
                }
            } else if keycode == VTKeyCode.right {
                if cursorIndex < text.endIndex {
                    cursorIndex = text.index(after: cursorIndex)
                }
            } else if keycode == VTKeyCode.up {
                if pos.line > 0 {
                    cursorIndex = getIndex(forVisualPosition: pos.line - 1, col: pos.col)
                } else {
                    cursorIndex = text.startIndex
                }
            } else if keycode == VTKeyCode.down {
                if pos.line < visualLines.count - 1 {
                    cursorIndex = getIndex(forVisualPosition: pos.line + 1, col: pos.col)
                } else {
                    cursorIndex = text.endIndex
                }
            }
            scrollToKeepCursorVisible()
            layer.invalidate()
            return
        }
        
        guard let char = event.character else { return }
        
        if char == "\u{03}" { // Ctrl+C handled globally usually, but if reaches here
            return
        } else if char == "\u{7F}" { // Backspace
            if cursorIndex > text.startIndex {
                let prev = text.index(before: cursorIndex)
                let distance = text.distance(from: text.startIndex, to: prev)
                text.remove(at: prev)
                cursorIndex = text.index(text.startIndex, offsetBy: distance)
                needsLayout = true
                layout(size: layer.frame.size)
                scrollToKeepCursorVisible()
                action(text)
            }
        } else if char == "\n" || char == "\r" {
            let distance = text.distance(from: text.startIndex, to: cursorIndex)
            text.insert("\n", at: cursorIndex)
            cursorIndex = text.index(text.startIndex, offsetBy: distance + 1)
            needsLayout = true
            layout(size: layer.frame.size)
            scrollToKeepCursorVisible()
            action(text)
        } else {
            let distance = text.distance(from: text.startIndex, to: cursorIndex)
            text.insert(char, at: cursorIndex)
            cursorIndex = text.index(text.startIndex, offsetBy: distance + 1)
            needsLayout = true
            layout(size: layer.frame.size)
            scrollToKeepCursorVisible()
            action(text)
        }
    }
    
    override func handleMouseEvent(_ event: MouseEvent) {
        if case .scroll(_, let deltaY) = event.type {
            let maxOffset = max(0, visualLines.count - layer.frame.size.height.intValue)
            contentOffset += Extended(deltaY)
            if contentOffset.intValue < 0 { contentOffset = 0 }
            if contentOffset.intValue > maxOffset { contentOffset = Extended(maxOffset) }
            
            // Constrain cursor to visible lines!
            let pos = getVisualPosition(for: cursorIndex)
            let frameHeight = layer.frame.size.height.intValue
            
            if pos.line < contentOffset.intValue {
                cursorIndex = getIndex(forVisualPosition: contentOffset.intValue, col: pos.col)
            } else if pos.line >= contentOffset.intValue + frameHeight {
                cursorIndex = getIndex(forVisualPosition: contentOffset.intValue + frameHeight - 1, col: pos.col)
            }
            
            layer.invalidate()
        } else if case .pressed(.left) = event.type {
            becomeFirstResponder()
            
            var globalLine = layer.frame.position.line.intValue
            var globalColumn = layer.frame.position.column.intValue
            var current = layer.parent
            while let p = current {
                globalLine += p.frame.position.line.intValue
                globalColumn += p.frame.position.column.intValue
                current = p.parent
            }
            
            let localY = event.position.line.intValue - globalLine
            let localX = event.position.column.intValue - globalColumn
            
            let visualY = localY + contentOffset.intValue
            let visualX = localX
            
            cursorIndex = getIndex(forVisualPosition: visualY, col: visualX)
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
