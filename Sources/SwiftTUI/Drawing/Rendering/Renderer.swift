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
        
        // Only redraw the dirty rect into the back buffer. Delta compression
        // compares front vs back; do not poison the front buffer on every paint
        // (that forced full-line terminal output even for single-cell edits).
        // Use `vtRenderer.invalidate(rect:)` explicitly when external corruption
        // (e.g. IME) needs a forced redraw.
        
        var buffer = ScreenBuffer(rect: rect)
        layer.draw(into: &buffer)
        
        for line in rect.minLine.intValue ... rect.maxLine.intValue {
            for column in rect.minColumn.intValue ... rect.maxColumn.intValue {
                let position = Position(column: Extended(column), line: Extended(line))
                if let cell = buffer.cell(at: position) {
                    drawPixel(cell, at: position)
                } else {
                    let vtPos = VTPosition(row: Int(line) + 1, column: Int(column) + 1)
                    if vtPos.column >= 1, vtPos.row >= 1,
                       vtPos.column <= layer.frame.size.width.intValue,
                       vtPos.row <= layer.frame.size.height.intValue {
                        vtRenderer?.back[vtPos] = VTCell(character: " ", style: VTStyle(foreground: nil, background: nil, attributes: []))
                    }
                }
            }
        }
    }

    func stop() {
        // VTRenderer will restore the terminal when we reset/stop
    }

    private func drawPixel(_ cell: Cell, at position: Position) {
        guard let vtRenderer = vtRenderer else { return }
        guard position.column >= 0, position.line >= 0, position.column < layer.frame.size.width, position.line < layer.frame.size.height else {
            return
        }

        // Convert SwiftTUI Color to VTColor
        let fg = convertColor(cell.foregroundColor)
        let bg = convertColor(cell.backgroundColor ?? .default)
        
        let attrs = cell.attributes
        var vtAttrs: VTAttributes = []
        if attrs.faint { vtAttrs.insert(.faint) }
        if attrs.bold { vtAttrs.insert(.bold) }
        if attrs.italic { vtAttrs.insert(.italic) }
        if attrs.underline { vtAttrs.insert(.underline) }
        if attrs.strikethrough { vtAttrs.insert(.strikethrough) }

        let vtPos = VTPosition(row: position.y + 1, column: position.x + 1)
        vtRenderer.back[vtPos] = VTCell(
            character: cell.char,
            style: VTStyle(
                foreground: fg,
                background: bg,
                attributes: vtAttrs
            )
        )
    }

    private func convertColor(_ color: Color) -> VTColor? {
        switch color {
        case .black: return .ansi(.black)
        case .red: return .ansi(.red)
        case .green: return .ansi(.green)
        case .yellow: return .ansi(.yellow)
        case .blue: return .ansi(.blue)
        case .magenta: return .ansi(.magenta)
        case .cyan: return .ansi(.cyan)
        case .white: return .ansi(.white)
        case .brightBlack: return .ansi(.black, intensity: .bright)
        case .brightRed: return .ansi(.red, intensity: .bright)
        case .brightGreen: return .ansi(.green, intensity: .bright)
        case .brightYellow: return .ansi(.yellow, intensity: .bright)
        case .brightBlue: return .ansi(.blue, intensity: .bright)
        case .brightMagenta: return .ansi(.magenta, intensity: .bright)
        case .brightCyan: return .ansi(.cyan, intensity: .bright)
        case .brightWhite: return .ansi(.white, intensity: .bright)
        case .default: return nil
        default: return nil
        }
    }
}
