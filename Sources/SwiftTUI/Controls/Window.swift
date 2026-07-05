import Foundation

@MainActor class Window: LayerDrawing {
    private(set) lazy var layer: Layer = makeLayer()

    private(set) var controls: [Control] = []

    var firstResponder: Control?

    func addControl(_ control: Control) {
        control.window = self
        self.controls.append(control)
        layer.addLayer(control.layer, at: 0)
    }

    private func makeLayer() -> Layer {
        let layer = Layer()
        layer.content = self
        return layer
    }

    func draw(into buffer: inout ScreenBuffer) {
        let cell = Cell(char: " ")
        for y in 0 ..< layer.frame.size.height.intValue {
            for x in 0 ..< layer.frame.size.width.intValue {
                buffer.setCell(cell, at: Position(column: Extended(x), line: Extended(y)))
            }
        }
    }
}
