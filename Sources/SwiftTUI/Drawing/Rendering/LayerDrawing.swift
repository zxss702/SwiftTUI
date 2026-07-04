import Foundation

@MainActor protocol LayerDrawing: AnyObject {
    func cell(at position: Position) -> Cell?
}

