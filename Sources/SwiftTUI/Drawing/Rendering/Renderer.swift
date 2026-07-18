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
            // Clear the dirty rect, expanding each cell to its full wide-char
            // span so we never leave an orphan lead / `\u{0000}` continuation.
            let maxCol = layer.frame.size.width.intValue
            let maxRow = layer.frame.size.height.intValue
            let empty = VTCell(character: " ", style: VTStyle(foreground: nil, background: nil, attributes: []))
            for line in rect.minLine.intValue ... rect.maxLine.intValue {
                var columns = Set<Int>()
                for column in rect.minColumn.intValue ... rect.maxColumn.intValue {
                    guard column >= 0, column < maxCol, line >= 0, line < maxRow else { continue }
                    columns.insert(column)
                    let vtPos = VTPosition(row: line + 1, column: column + 1)
                    let ch = vtRenderer.back[vtPos].character
                    if ch == "\u{0000}", column > 0 {
                        columns.insert(column - 1)
                    } else if ch.width > 1, column + 1 < maxCol {
                        columns.insert(column + 1)
                    }
                }
                for column in columns {
                    let vtPos = VTPosition(row: line + 1, column: column + 1)
                    if vtPos.column >= 1, vtPos.row >= 1,
                       vtPos.column <= maxCol, vtPos.row <= maxRow
                    {
                        vtRenderer.back[vtPos] = empty
                    }
                }
            }
        }
        
        // When vtRenderer is injected, ScreenBuffer directly maps TUI Cell writes to VTCell.
        var buffer = ScreenBuffer(rect: rect, vtRenderer: vtRenderer)
        layer.draw(into: &buffer)

        // Top-level selection highlight: applied over the final frame so it is
        // always aligned with what is actually on screen (wide characters,
        // overlapping views). Views never draw this themselves.
        application?.window.selectionCoordinator.applyHighlight(into: &buffer)
    }

    func stop() {
        // VTRenderer will restore the terminal when we reset/stop
    }
}
