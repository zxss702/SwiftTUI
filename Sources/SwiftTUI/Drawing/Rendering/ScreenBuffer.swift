import Foundation

@MainActor
struct ScreenBuffer {
    let rect: Rect
    weak var vtRenderer: VTRenderer?
    private var cells: [Cell?]?
    
    var translation: Position = .zero
    var clipRect: Rect
    
    private var stateStack: [(translation: Position, clipRect: Rect)] = []
    
    init(rect: Rect, vtRenderer: VTRenderer? = nil) {
        self.rect = rect
        self.clipRect = rect
        self.vtRenderer = vtRenderer
        
        if vtRenderer == nil {
            if rect.size.width.intValue <= 0 || rect.size.height.intValue <= 0 {
                self.cells = []
            } else {
                self.cells = Array(repeating: nil, count: rect.size.width.intValue * rect.size.height.intValue)
            }
        }
    }
    
    mutating func saveState() {
        stateStack.append((translation, clipRect))
    }
    
    mutating func restoreState() {
        if let state = stateStack.popLast() {
            translation = state.translation
            clipRect = state.clipRect
        }
    }
    
    mutating func translate(by offset: Position) {
        translation = translation + offset
    }
    
    mutating func clip(to rect: Rect) {
        let translatedRect = Rect(position: rect.position + translation, size: rect.size)
        clipRect = clipRect.intersection(with: translatedRect) ?? .zero
    }
    
    mutating func setCell(_ cell: Cell, at position: Position) {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return }
        
        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0, localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue else { return }
        
        if let vt = vtRenderer {
            let vtPos = VTPosition(row: finalPos.y + 1, column: finalPos.x + 1)
            let vtCell = vt.back[vtPos]
            
            let fg = convertColor(cell.foregroundColor)
            var bg = convertColor(cell.backgroundColor ?? .default)
            
            if cell.backgroundColor == nil {
                bg = vtCell.style.background
            }
            
            var vtAttrs: VTAttributes = []
            if cell.attributes.faint { vtAttrs.insert(.faint) }
            if cell.attributes.bold { vtAttrs.insert(.bold) }
            if cell.attributes.italic { vtAttrs.insert(.italic) }
            if cell.attributes.underline { vtAttrs.insert(.underline) }
            if cell.attributes.strikethrough { vtAttrs.insert(.strikethrough) }
            
            vt.back[vtPos] = VTCell(
                character: cell.char,
                style: VTStyle(foreground: fg, background: bg, attributes: vtAttrs)
            )
        } else if var cells {
            let index = localPos.y * rect.size.width.intValue + localPos.x
            guard index >= 0 && index < cells.count else { return }

            if let existing = cells[index] {
                var newCell = cell
                if newCell.backgroundColor == nil {
                    newCell.backgroundColor = existing.backgroundColor
                }
                cells[index] = newCell
            } else {
                cells[index] = cell
            }
            self.cells = cells
        }
    }
    
    func cell(at position: Position) -> Cell? {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return nil }
        
        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0, localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue else { return nil }
        
        if vtRenderer != nil {
            // Cannot accurately reconstruct a SwiftTUI.Cell from VTCell without loss, 
            // but this is mostly used by Renderer.draw to copy back to VT. 
            // If vtRenderer is used, cell(at:) shouldn't be called.
            return nil
        }
        
        guard let cells = cells else { return nil }
        let index = localPos.y * rect.size.width.intValue + localPos.x
        guard index >= 0 && index < cells.count else { return nil }
        return cells[index]
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
