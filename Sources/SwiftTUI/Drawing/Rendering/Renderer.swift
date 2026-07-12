import Foundation

@MainActor class Renderer {
    var layer: Layer
    weak var application: Application?
    var vtRenderer: VTRenderer?

    init(layer: Layer) {
        self.layer = layer
    }

    func update() {
        if let invalidated = layer.invalidated {
            draw(rect: invalidated)
            layer.invalidated = nil
        }
    }

    func draw(rect: Rect? = nil) {
        if rect == nil { layer.invalidated = nil }
        let rect = rect ?? Rect(position: .zero, size: layer.frame.size)
        guard rect.size.width > 0, rect.size.height > 0 else {
            return
        }
        
        if let vtRenderer = vtRenderer {
            // Clear the dirty rect in the VT back buffer before drawing the layer tree
            for line in rect.minLine.intValue ... rect.maxLine.intValue {
                for column in rect.minColumn.intValue ... rect.maxColumn.intValue {
                    let vtPos = VTPosition(row: Int(line) + 1, column: Int(column) + 1)
                    if vtPos.column >= 1, vtPos.row >= 1,
                       vtPos.column <= layer.frame.size.width.intValue,
                       vtPos.row <= layer.frame.size.height.intValue {
                        vtRenderer.back[vtPos] = VTCell(character: " ", style: VTStyle(foreground: nil, background: nil, attributes: []))
                    }
                }
            }
        }
        
        // When vtRenderer is injected, ScreenBuffer directly maps TUI Cell writes to VTCell.
        var buffer = ScreenBuffer(rect: rect, vtRenderer: vtRenderer)
        layer.draw(into: &buffer)
    }

    func stop() {
        // VTRenderer will restore the terminal when we reset/stop
    }
}
