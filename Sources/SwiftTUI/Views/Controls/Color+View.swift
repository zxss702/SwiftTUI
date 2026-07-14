import Foundation

extension Color: View, PrimitiveView {
    static var size: Int? { 1 }
    
    func buildNode(_ node: Node) {
        node.element = ColorElement(color: self)
    }
    
    func updateNode(_ node: Node) {
        let last = node.view as! Self
        node.view = self
        if self != last {
            let control = node.element as! ColorElement
            control.color = self
            control.layer.invalidate()
        }
    }
    
    private class ColorElement: Element {
        var color: Color
        
        init(color: Color) {
            self.color = color
        }
        
        override func draw(into buffer: inout ScreenBuffer) {
            let cell = Cell(char: " ", backgroundColor: color)
            for y in 0 ..< layer.frame.size.height.intValue {
                for x in 0 ..< layer.frame.size.width.intValue {
                    buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
                }
            }
        }
    }
}
