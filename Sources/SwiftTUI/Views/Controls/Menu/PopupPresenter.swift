import Foundation
import Observation

// MARK: - PopupPresenter

/// 应用级悬浮弹出层。面板不参与原有布局，叠在 Application 最上层。
@Observable
@MainActor
public final class PopupPresenter {
    private(set) var presentationID: UUID?

    @ObservationIgnored
    private(set) var panel: AnyView?

    @ObservationIgnored
    private(set) var anchor: Rect = .zero

    @ObservationIgnored
    var panelFrame: Rect?

    @ObservationIgnored
    private var onDismissHandlers: [() -> Void] = []

    public var isPresented: Bool { presentationID != nil }

    public func present<V: View>(
        anchor: Rect,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        if presentationID != nil {
            let previous = onDismissHandlers
            onDismissHandlers = []
            for handler in previous { handler() }
        }
        self.anchor = anchor
        self.panelFrame = nil
        self.panel = AnyView(PopupMenuPanel(content: content()))
        self.onDismissHandlers = [onDismiss]
        self.presentationID = UUID()
    }

    /// 无明确锚点时，居中偏上显示。
    public func presentCentered<V: View>(
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        present(
            anchor: Rect(position: Position(column: 2, line: 2), size: Size(width: 1, height: 1)),
            onDismiss: onDismiss,
            content: content
        )
    }

    public func dismiss() {
        guard presentationID != nil else { return }
        presentationID = nil
        panel = nil
        panelFrame = nil
        anchor = .zero
        let handlers = onDismissHandlers
        onDismissHandlers = []
        for handler in handlers { handler() }
    }
}

// MARK: - Overlay host（View 层跟踪 presentationID）

@MainActor
struct PopupOverlayHost: View {
    @Environment(PopupPresenter.self) private var presenter

    var body: some View {
        let _ = presenter.presentationID
        if presenter.presentationID != nil, let panel = presenter.panel {
            FloatingPopupLayer(anchor: presenter.anchor, presenter: presenter, panel: panel)
        }
    }
}

// MARK: - 悬浮层 Control：命中穿透 + 锚点定位

@MainActor
private struct FloatingPopupLayer: View, PrimitiveView {
    let anchor: Rect
    let presenter: PopupPresenter
    let panel: AnyView

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: panel.view))
        let control = FloatingPopupControl(anchor: anchor, presenter: presenter)
        control.panelControl = node.children[0].control(at: 0)
        control.addSubview(control.panelControl, at: 0)
        node.control = control

        DispatchQueue.main.async {
            guard let window = control.window else { return }
            window.firstResponder?.resignFirstResponder()
            window.firstResponder = control
            control.becomeFirstResponder()
        }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: panel.view)
        let control = node.control as! FloatingPopupControl
        control.anchor = anchor
        control.presenter = presenter
        control.panelControl = node.children[0].control(at: 0)
        control.layer.invalidate()
    }
}

@MainActor
private final class FloatingPopupControl: Control {
    var anchor: Rect
    weak var presenter: PopupPresenter?
    var panelControl: Control!

    init(anchor: Rect, presenter: PopupPresenter) {
        self.anchor = anchor
        self.presenter = presenter
    }

    override var selectable: Bool { true }

    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelControl else { return }

        let spaceBelow = max(Extended(1), size.height - (anchor.position.line + max(anchor.size.height, 1)))
        let spaceAbove = max(Extended(1), anchor.position.line)
        let maxHeight = max(spaceBelow, spaceAbove)

        let measured = panelControl.size(
            proposedSize: Size(width: max(anchor.size.width + 8, 24), height: maxHeight)
        )
        let panelSize = Size(
            width: min(max(measured.width, 8), size.width),
            height: min(max(measured.height, 1), maxHeight)
        )
        panelControl.layout(size: panelSize)

        // 水平：菜单右边优先对齐触发器（箭头）右边；左侧不够则向右溢出（贴左）
        let anchorTrailing = anchor.position.column + max(anchor.size.width, 1)
        var column = anchorTrailing - panelSize.width
        if column < 0 {
            column = 0
        }
        if column + panelSize.width > size.width {
            column = max(0, size.width - panelSize.width)
        }

        var line = anchor.position.line + max(anchor.size.height, 1)
        // 下方放不下则翻到上方
        if line + panelSize.height > size.height, spaceAbove >= spaceBelow {
            line = max(0, anchor.position.line - panelSize.height)
        }
        if line + panelSize.height > size.height {
            line = max(0, size.height - panelSize.height)
        }
        panelControl.layer.frame.position = Position(column: column, line: line)
        presenter?.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    /// 只有点在面板上才命中；其余返回 nil，事件落到下层内容。
    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        guard let panelControl else { return nil }
        return panelControl.hitTest(position: local)
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            presenter?.dismiss()
            return
        }
        super.handleKeyEvent(event)
    }
}

// MARK: - 圆角面板（无额外 padding；超出可滚动）

@MainActor
struct PopupMenuPanel<Content: View>: View {
    let content: Content

    init(content: Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            content
        }
        .background(.default)
        .border(.rounded)
    }
}

// MARK: - 触发按钮（回调绝对 frame）

@MainActor
struct PopupAnchorButton<Label: View>: View, PrimitiveView {
    let label: Label
    let action: (Rect) -> Void

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: VStack(content: label).view))
        let control = PopupAnchorButtonControl(action: action)
        control.label = node.children[0].control(at: 0)
        control.addSubview(control.label, at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: VStack(content: label).view)
        (node.control as! PopupAnchorButtonControl).action = action
    }
}

@MainActor
private final class PopupAnchorButtonControl: Control {
    var action: (Rect) -> Void
    var label: Control!
    private weak var buttonLayer: AnchorButtonLayer?

    init(action: @escaping (Rect) -> Void) {
        self.action = action
    }

    override func size(proposedSize: Size) -> Size {
        label.size(proposedSize: proposedSize)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        label.layout(size: size)
    }

    override func handleEvent(_ char: Character) {
        if char == "\n" || char == " " {
            action(absoluteFrame)
        }
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        if case .released(.left) = event.type {
            action(absoluteFrame)
        } else {
            super.handleMouseEvent(event)
        }
    }

    override func hoveredStateDidChange() {
        buttonLayer?.highlighted = isHovered
        layer.invalidate()
    }

    override func makeLayer() -> Layer {
        let layer = AnchorButtonLayer()
        buttonLayer = layer
        return layer
    }
}

@MainActor
private final class AnchorButtonLayer: Layer {
    var highlighted = false

    override func draw(into buffer: inout ScreenBuffer) {
        super.draw(into: &buffer)
        if highlighted {
            for y in 0 ..< frame.size.height.intValue {
                for x in 0 ..< frame.size.width.intValue {
                    let pos = Position(column: Extended(x), line: Extended(y))
                    if var cell = buffer.cell(at: pos) {
                        cell.attributes.inverted.toggle()
                        buffer.setCell(cell, at: pos)
                    }
                }
            }
        }
    }
}
