import Foundation

@MainActor public struct TextField: View, PrimitiveView {
    public let placeholder: String?
    public let action: (String) -> Void

    @Environment(\.placeholderColor) private var placeholderColor: Color

    public init(placeholder: String? = nil, action: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.action = action
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.control = TextFieldControl(placeholder: placeholder ?? "", placeholderColor: placeholderColor, action: action)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        (node.control as! TextFieldControl).action = action
    }

    private class TextFieldControl: Control {
        var placeholder: String
        var placeholderColor: Color
        var action: (String) -> Void

        var text: String = ""

        init(placeholder: String, placeholderColor: Color, action: @escaping (String) -> Void) {
            self.placeholder = placeholder
            self.placeholderColor = placeholderColor
            self.action = action
        }

        override func size(proposedSize: Size) -> Size {
            return Size(width: Extended(max(text.width, placeholder.width)) + 1, height: 1)
        }

        override func handleEvent(_ char: Character) {
            if char == "\n" {
                action(text)
                self.text = ""
                layer.invalidate()
                return
            }

            if char == ASCII.DEL {
                if !self.text.isEmpty {
                    self.text.removeLast()
                    layer.invalidate()
                }
                return
            }

            self.text += String(char)
            layer.invalidate()
        }

        override var cursorPosition: Position? {
            guard isFirstResponder else { return nil }
            return Position(column: Extended(text.width), line: 0)
        }

        override func draw(into buffer: inout ScreenBuffer) {
            var currentWidth = 0
            
            if text.isEmpty {
                for i in placeholder.indices {
                    let charWidth = placeholder[i].width
                    buffer.setCell(Cell(char: placeholder[i], foregroundColor: placeholderColor), at: Position(column: Extended(currentWidth), line: 0))
                    for w in 1 ..< charWidth {
                        buffer.setCell(Cell(char: "\u{0000}", foregroundColor: placeholderColor), at: Position(column: Extended(currentWidth + w), line: 0))
                    }
                    currentWidth += charWidth
                }
            } else {
                for i in text.indices {
                    let charWidth = text[i].width
                    buffer.setCell(Cell(char: text[i]), at: Position(column: Extended(currentWidth), line: 0))
                    for w in 1 ..< charWidth {
                        buffer.setCell(Cell(char: "\u{0000}"), at: Position(column: Extended(currentWidth + w), line: 0))
                    }
                    currentWidth += charWidth
                }
            }
            
            let maxWidth = layer.frame.size.width.intValue
            for w in currentWidth ..< maxWidth {
                buffer.setCell(Cell(char: " "), at: Position(column: Extended(w), line: 0))
            }
        }

        override var selectable: Bool { true }

        override func becomeFirstResponder() {
            super.becomeFirstResponder()
            layer.invalidate()
        }

        override func resignFirstResponder() {
            super.resignFirstResponder()
            layer.invalidate()
        }
    }
}

extension EnvironmentValues {
    public var placeholderColor: Color {
        get { self[PlaceholderColorEnvironmentKey.self] }
        set { self[PlaceholderColorEnvironmentKey.self] = newValue }
    }
}

private struct PlaceholderColorEnvironmentKey: EnvironmentKey {
    static var defaultValue: Color { .default }
}
