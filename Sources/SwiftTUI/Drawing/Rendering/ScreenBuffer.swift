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
    
    /// Write a cell with wide-character (CJK / emoji) awareness:
    /// - `\u{0000}` → raw continuation store (legacy callers)
    /// - width 0 → ignored
    /// - landing on a continuation → blank the straddled char's lead, write in place
    /// - width 2 → lead + continuation, then clear any orphaned continuation after
    /// - width 1 → clear orphan continuation to the right
    ///
    /// Later writes win in place (standard terminal-grid semantics): a sheet /
    /// popup border landing on the continuation cell of an underlying CJK char
    /// must stay on its requested column — the old "retreat to lead" shifted
    /// the border one cell left and tore the panel rectangle. The straddled
    /// lower character is blanked instead (upper layer has priority).
    mutating func setCell(_ cell: Cell, at position: Position) {
        if cell.char == "\u{0000}" {
            writeRaw(cell, at: position)
            return
        }
        let cw = cell.char.width
        guard cw > 0 else { return }

        if character(at: position) == "\u{0000}", position.column.intValue > 0 {
            blankRaw(at: Position(column: position.column - 1, line: position.line))
        }

        writeRaw(cell, at: position)
        if cw > 1 {
            var cont = cell
            cont.char = "\u{0000}"
            for w in 1 ..< cw {
                writeRaw(
                    cont,
                    at: Position(column: position.column + Extended(w), line: position.line)
                )
            }
        }
        // The cell after this write may be an orphaned continuation (its lead
        // was just overwritten). Blank it, keeping the lower layer's style so
        // panel colors do not bleed past a border.
        let next = Position(column: position.column + Extended(cw), line: position.line)
        if character(at: next) == "\u{0000}" {
            blankRaw(at: next)
        }
    }

    /// Replace a cell's glyph with a space while keeping its existing style
    /// (used to erase halves of straddled wide characters).
    private mutating func blankRaw(at position: Position) {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return }

        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0,
              localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue
        else { return }

        if let vt = vtRenderer {
            let vtPos = VTPosition(row: finalPos.y + 1, column: finalPos.x + 1)
            let existing = vt.back[vtPos]
            vt.back[vtPos] = VTCell(character: " ", style: existing.style)
        } else if var cells {
            let index = localPos.y * rect.size.width.intValue + localPos.x
            guard index >= 0 && index < cells.count else { return }
            var cell = cells[index] ?? Cell(char: " ")
            cell.char = " "
            cells[index] = cell
            self.cells = cells
        }
    }

    /// Single-column store without grapheme expansion (internal / continuation).
    private mutating func writeRaw(_ cell: Cell, at position: Position) {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return }
        
        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0,
              localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue
        else { return }
        
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
    
    /// Re-styles an already-drawn cell (text selection highlight): keeps the
    /// character and attributes, swaps background (and optionally foreground).
    mutating func highlightCell(at position: Position, background: Color, foreground: Color?) {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return }

        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0,
              localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue
        else { return }

        if let vt = vtRenderer {
            let vtPos = VTPosition(row: finalPos.y + 1, column: finalPos.x + 1)
            let existing = vt.back[vtPos]
            vt.back[vtPos] = VTCell(
                character: existing.character,
                style: VTStyle(
                    foreground: foreground?.vtColor ?? existing.style.foreground,
                    background: background.vtColor,
                    attributes: existing.style.attributes
                )
            )
        } else if var cells {
            let index = localPos.y * rect.size.width.intValue + localPos.x
            guard index >= 0 && index < cells.count else { return }
            var cell = cells[index] ?? Cell(char: " ")
            cell.backgroundColor = background
            if let foreground { cell.foregroundColor = foreground }
            cells[index] = cell
            self.cells = cells
        }
    }

    /// Dim an already-drawn cell without replacing its glyph (sheet scrim).
    /// VT `cell(at:)` cannot rebuild a TUI `Cell`, so this path reads the VT
    /// back buffer / headless store directly and only inserts `.faint`.
    mutating func dimCell(at position: Position) {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return }

        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0,
              localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue
        else { return }

        if let vt = vtRenderer {
            let vtPos = VTPosition(row: finalPos.y + 1, column: finalPos.x + 1)
            let existing = vt.back[vtPos]
            var attrs = existing.style.attributes
            attrs.insert(.faint)
            vt.back[vtPos] = VTCell(
                character: existing.character,
                style: VTStyle(
                    foreground: existing.style.foreground,
                    background: existing.style.background,
                    attributes: attrs
                )
            )
        } else if var cells {
            let index = localPos.y * rect.size.width.intValue + localPos.x
            guard index >= 0 && index < cells.count else { return }
            var cell = cells[index] ?? Cell(char: " ")
            cell.attributes.faint = true
            cells[index] = cell
            self.cells = cells
        }
    }

    /// Reads the character already drawn at `position` (both VT and headless
    /// paths). Returns `nil` when the position is clipped away. Wide-character
    /// continuation cells report `\u{0000}`.
    func character(at position: Position) -> Character? {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return nil }

        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0,
              localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue
        else { return nil }

        if let vt = vtRenderer {
            let vtPos = VTPosition(row: finalPos.y + 1, column: finalPos.x + 1)
            return vt.back[vtPos].character
        }
        guard let cells else { return nil }
        let index = localPos.y * rect.size.width.intValue + localPos.x
        guard index >= 0 && index < cells.count else { return nil }
        return cells[index]?.char
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
        color.vtColor
    }
}
