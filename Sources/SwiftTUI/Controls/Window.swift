import Foundation

@MainActor class Window: LayerDrawing {
    private(set) lazy var layer: Layer = makeLayer()

    private(set) var controls: [Control] = []

    var firstResponder: Control?

    /// 拖动手势等：按下后捕获 move/release，避免 hitTest 随光标漂移。
    weak var mouseCapture: Control?

    /// 应用级弹出层；由 `Application` 注入，供弹出菜单等 Control 回调使用。
    weak var popupPresenter: PopupPresenter?

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
