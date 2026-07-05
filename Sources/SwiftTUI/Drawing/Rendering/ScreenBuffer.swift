import Foundation

@MainActor
struct ScreenBuffer {
    let rect: Rect
    private var cells: [Cell?]
    
    var translation: Position = .zero
    var clipRect: Rect
    
    private var stateStack: [(translation: Position, clipRect: Rect)] = []
    
    init(rect: Rect) {
        self.rect = rect
        self.clipRect = rect
        if rect.size.width.intValue <= 0 || rect.size.height.intValue <= 0 {
            self.cells = []
        } else {
            self.cells = Array(repeating: nil, count: rect.size.width.intValue * rect.size.height.intValue)
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
    }
    
    func cell(at position: Position) -> Cell? {
        let finalPos = position + translation
        guard clipRect.contains(finalPos) else { return nil }
        
        let localPos = finalPos - rect.position
        guard localPos.x >= 0, localPos.y >= 0, localPos.x < rect.size.width.intValue, localPos.y < rect.size.height.intValue else { return nil }
        
        let index = localPos.y * rect.size.width.intValue + localPos.x
        guard index >= 0 && index < cells.count else { return nil }
        return cells[index]
    }
}
