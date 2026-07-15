import Foundation

public extension View {
    func border(_ color: Color? = nil, style: BorderStyle = .default) -> some View {
        return Border(content: self, color: color, style: style)
    }
  
    func border(_ style: BorderStyle = .default) -> some View {
        Border(content: self, color: nil, style: style)
    }
}

@MainActor public struct BorderStyle: Equatable {
    let topLeft: Character
    let top: Character
    let topRight: Character
    let left: Character
    let right: Character
    let bottomLeft: Character
    let bottom: Character
    let bottomRight: Character

    public init(topLeft: Character, top: Character, topRight: Character, left: Character, right: Character, bottomLeft: Character, bottom: Character, bottomRight: Character) {
        self.topLeft = topLeft
        self.top = top
        self.topRight = topRight
        self.left = left
        self.right = right
        self.bottomLeft = bottomLeft
        self.bottom = bottom
        self.bottomRight = bottomRight
    }

    public init(topLeft: Character, topRight: Character, bottomLeft: Character, bottomRight: Character, horizontal: Character, vertical: Character) {
        self.topLeft = topLeft
        self.top = horizontal
        self.topRight = topRight
        self.left = vertical
        self.right = vertical
        self.bottomLeft = bottomLeft
        self.bottom = horizontal
        self.bottomRight = bottomRight
    }

    /// ```
    /// ┌──┐
    /// └──┘
    /// ```
    public static var `default`: BorderStyle {
        BorderStyle(topLeft: "┌", topRight: "┐", bottomLeft: "└", bottomRight: "┘", horizontal: "─", vertical: "│")
    }

    /// ```
    /// ╭──╮
    /// ╰──╯
    /// ```
    public static var rounded: BorderStyle {
        BorderStyle(topLeft: "╭", topRight: "╮", bottomLeft: "╰", bottomRight: "╯", horizontal: "─", vertical: "│")
    }

    /// ```
    /// ┏━━┓
    /// ┗━━┛
    /// ```
    public static var heavy: BorderStyle {
        BorderStyle(topLeft: "┏", topRight: "┓", bottomLeft: "┗", bottomRight: "┛", horizontal: "━", vertical: "┃")
    }

    /// ```
    /// ╔══╗
    /// ╚══╝
    /// ```
    public static var double: BorderStyle {
        BorderStyle(topLeft: "╔", topRight: "╗", bottomLeft: "╚", bottomRight: "╝", horizontal: "═", vertical: "║")
    }
}

private struct Border<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let color: Color?
    let style: BorderStyle
    @Environment(\.foregroundColor) var foregroundColor: Color
    
    static var size: Int? { Content.size }
    
    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.elements = WeakSet<Element>()
        node.addNode(at: 0, Node(view: content.view))
    }
    
    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.elements?.values ?? [] {
            let control = control as! BorderElement
            if control.color != color || control.style != style {
                control.color = color ?? foregroundColor
                control.style = style
                control.layer.invalidate()
            }
        }
    }
    
    func passElement(_ control: Element, node: Node) -> Element {
        if let borderElement = control.parent as? BorderElement {
            borderElement.color = color ?? foregroundColor
            borderElement.style = style
            return borderElement
        }
        let borderElement = BorderElement(color: color ?? foregroundColor, style: style)
        borderElement.addSubview(control, at: 0)
        node.elements?.add(borderElement)
        return borderElement
    }
    
    private class BorderElement: Element {
        var color: Color
        var style: BorderStyle

        /// Border glyphs sit outside the child frame; donate so clicks still focus
        /// an inner TextField / Button (SwiftUI hit-testing through chrome).
        override var donatesDescendantPointerOnClick: Bool { true }

        init(color: Color, style: BorderStyle) {
            self.color = color
            self.style = style
        }
        
        override func size(proposedSize: Size) -> Size {
            var proposedSize = proposedSize
            proposedSize.width -= 2
            proposedSize.height -= 2
            var size = children[0].size(proposedSize: proposedSize)
            size.width += 2
            size.height += 2
            return size
        }
        
        override func layout(size: Size) {
            var contentSize = size
            contentSize.width -= 2
            contentSize.height -= 2
            children[0].layout(size: contentSize)
            let oldFrame = children[0].layer.frame
            children[0].layer.frame.position = Position(column: 1, line: 1)
            if oldFrame != children[0].layer.frame {
                self.layer.invalidate(rect: oldFrame)
                self.layer.invalidate(rect: children[0].layer.frame)
            }
            self.layer.frame.size = size
        }
        
        override func draw(into buffer: inout ScreenBuffer) {
            let width = layer.frame.size.width.intValue
            let height = layer.frame.size.height.intValue
            guard width > 0, height > 0 else { return }
            
            for x in 1 ..< width - 1 {
                buffer.setCell(Cell(char: style.top, foregroundColor: color), at: Position(column: Extended(x), line: 0))
                if height > 1 {
                    buffer.setCell(Cell(char: style.bottom, foregroundColor: color), at: Position(column: Extended(x), line: Extended(height - 1)))
                }
            }
            
            for y in 1 ..< height - 1 {
                buffer.setCell(Cell(char: style.left, foregroundColor: color), at: Position(column: 0, line: Extended(y)))
                if width > 1 {
                    buffer.setCell(Cell(char: style.right, foregroundColor: color), at: Position(column: Extended(width - 1), line: Extended(y)))
                }
            }
            
            buffer.setCell(Cell(char: style.topLeft, foregroundColor: color), at: Position(column: 0, line: 0))
            if width > 1 {
                buffer.setCell(Cell(char: style.topRight, foregroundColor: color), at: Position(column: Extended(width - 1), line: 0))
            }
            if height > 1 {
                buffer.setCell(Cell(char: style.bottomLeft, foregroundColor: color), at: Position(column: 0, line: Extended(height - 1)))
            }
            if width > 1 && height > 1 {
                buffer.setCell(Cell(char: style.bottomRight, foregroundColor: color), at: Position(column: Extended(width - 1), line: Extended(height - 1)))
            }
        }
    }
}
