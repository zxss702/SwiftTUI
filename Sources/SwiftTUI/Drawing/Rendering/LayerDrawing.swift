import Foundation

@MainActor protocol LayerDrawing: AnyObject {
    func draw(into buffer: inout ScreenBuffer)
}

