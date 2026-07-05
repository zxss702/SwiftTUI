import Foundation

@MainActor public struct Text: View, PrimitiveView {
    private var text: String?
    
    private var _attributedText: Any?
    
    @available(macOS 12, *)
    private var attributedText: AttributedString? { _attributedText as? AttributedString }
    
    @Environment(\.foregroundColor) private var foregroundColor: Color
    @Environment(\.bold) private var bold: Bool
    @Environment(\.italic) private var italic: Bool
    @Environment(\.underline) private var underline: Bool
    @Environment(\.strikethrough) private var strikethrough: Bool
    
    public init(_ text: String) {
        self.text = text
    }
    
    @available(macOS 12, *)
    public init(_ attributedText: AttributedString) {
        self._attributedText = attributedText
    }
    
    static var size: Int? { 1 }
    
    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.control = TextControl(
            text: text,
            attributedText: _attributedText,
            foregroundColor: foregroundColor,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough
        )
    }
    
    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextControl
        control.text = text
        control._attributedText = _attributedText
        control.foregroundColor = foregroundColor
        control.bold = bold
        control.italic = italic
        control.underline = underline
        control.strikethrough = strikethrough
        control.layer.invalidate()
    }
    
    private class TextControl: Control {
        var text: String?
        
        var _attributedText: Any?
        
        @available(macOS 12, *)
        var attributedText: AttributedString? { _attributedText as? AttributedString }
        
        var foregroundColor: Color
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var strikethrough: Bool
        
        init(
            text: String?,
            attributedText: Any?,
            foregroundColor: Color,
            bold: Bool,
            italic: Bool,
            underline: Bool,
            strikethrough: Bool
        ) {
            self.text = text
            self._attributedText = attributedText
            self.foregroundColor = foregroundColor
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
        }
        
        override func size(proposedSize: Size) -> Size {
            return Size(width: Extended(visualWidth), height: 1)
        }
        
        override func draw(into buffer: inout ScreenBuffer) {
            var currentWidth = 0
            
            if #available(macOS 12, *), let attributedText {
                let characters = attributedText.characters
                for i in characters.indices {
                    let charWidth = characters[i].width
                    let char = attributedText[i ..< characters.index(after: i)]
                    let cellAttributes = CellAttributes(
                        bold: char.bold ?? bold,
                        italic: char.italic ?? italic,
                        underline: char.underline ?? underline,
                        strikethrough: char.strikethrough ?? strikethrough,
                        inverted: char.inverted ?? false
                    )
                    
                    let cell = Cell(
                        char: char.characters[char.startIndex],
                        foregroundColor: char.foregroundColor ?? foregroundColor,
                        backgroundColor: char.backgroundColor,
                        attributes: cellAttributes
                    )
                    
                    buffer.setCell(cell, at: Position(column: Extended(currentWidth), line: 0))
                    
                    for w in 1 ..< charWidth {
                        let paddingCell = Cell(
                            char: "\u{0000}",
                            foregroundColor: char.foregroundColor ?? foregroundColor,
                            backgroundColor: char.backgroundColor,
                            attributes: cellAttributes
                        )
                        buffer.setCell(paddingCell, at: Position(column: Extended(currentWidth + w), line: 0))
                    }
                    
                    currentWidth += charWidth
                }
            } else if let text {
                for i in text.indices {
                    let charWidth = text[i].width
                    let cellAttributes = CellAttributes(
                        bold: bold,
                        italic: italic,
                        underline: underline,
                        strikethrough: strikethrough
                    )
                    let cell = Cell(
                        char: text[i],
                        foregroundColor: foregroundColor,
                        attributes: cellAttributes
                    )
                    
                    buffer.setCell(cell, at: Position(column: Extended(currentWidth), line: 0))
                    
                    for w in 1 ..< charWidth {
                        let paddingCell = Cell(
                            char: "\u{0000}",
                            foregroundColor: foregroundColor,
                            attributes: cellAttributes
                        )
                        buffer.setCell(paddingCell, at: Position(column: Extended(currentWidth + w), line: 0))
                    }
                    
                    currentWidth += charWidth
                }
            }
            
            let maxWidth = layer.frame.size.width.intValue
            for w in currentWidth ..< maxWidth {
                buffer.setCell(Cell(char: " "), at: Position(column: Extended(w), line: 0))
            }
        }
        
        private var visualWidth: Int {
            if #available(macOS 12, *), let attributedText {
                return String(attributedText.characters).width
            }
            return text?.width ?? 0
        }
    }
}
