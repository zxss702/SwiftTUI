import Foundation
import Observation

// MARK: - Kind

enum PopupKind: Equatable {
    case menu
    case sheet
    case popover
    case alert
}

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
    private(set) var kind: PopupKind = .menu

    @ObservationIgnored
    var panelFrame: Rect?

    @ObservationIgnored
    private var onDismissHandlers: [() -> Void] = []

    public var isPresented: Bool { presentationID != nil }

    /// sheet / alert：外点不穿透，由遮罩吞掉点击。
    var blocksUnderlyingHits: Bool {
        kind == .sheet || kind == .alert
    }

    // MARK: - Menu（现有）

    public func present<V: View>(
        anchor: Rect,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        present(
            kind: .menu,
            anchor: anchor,
            onDismiss: onDismiss,
            panel: AnyView(PopupMenuPanel(content: content()))
        )
    }

    /// 无明确锚点时，居中偏上显示（菜单样式）。
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

    // MARK: - Sheet / Popover / Alert

    func presentSheet<V: View>(
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        present(
            kind: .sheet,
            anchor: .zero,
            onDismiss: onDismiss,
            panel: AnyView(SheetPanel(content: dismissable(content())))
        )
    }

    func presentPopover<V: View>(
        anchor: Rect,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        present(
            kind: .popover,
            anchor: anchor,
            onDismiss: onDismiss,
            panel: AnyView(PopoverPanel(content: dismissable(content())))
        )
    }

    func presentAlert<V: View>(
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) {
        present(
            kind: .alert,
            anchor: .zero,
            onDismiss: onDismiss,
            panel: AnyView(AlertPanel(content: dismissable(content())))
        )
    }

    public func dismiss() {
        guard presentationID != nil else { return }
        presentationID = nil
        panel = nil
        panelFrame = nil
        anchor = .zero
        kind = .menu
        let handlers = onDismissHandlers
        onDismissHandlers = []
        for handler in handlers { handler() }
    }

    // MARK: - Private

    private func present(kind: PopupKind, anchor: Rect, onDismiss: @escaping () -> Void, panel: AnyView) {
        if presentationID != nil {
            let previous = onDismissHandlers
            onDismissHandlers = []
            for handler in previous { handler() }
        }
        self.kind = kind
        self.anchor = anchor
        self.panelFrame = nil
        self.panel = panel
        self.onDismissHandlers = [onDismiss]
        self.presentationID = UUID()
    }

    private func dismissable<V: View>(_ content: V) -> some View {
        content.environment(\.dismiss, DismissAction { [weak self] in
            self?.dismiss()
        })
    }
}

// MARK: - Overlay host

@MainActor
struct PopupOverlayHost: View {
    @Environment(PopupPresenter.self) private var presenter

    var body: some View {
        let _ = presenter.presentationID
        if presenter.presentationID != nil, let panel = presenter.panel {
            switch presenter.kind {
            case .menu:
                FloatingPopupLayer(anchor: presenter.anchor, presenter: presenter, panel: panel)
            case .popover:
                PopoverFloatingLayer(anchor: presenter.anchor, presenter: presenter, panel: panel)
            case .sheet, .alert:
                ModalFloatingLayer(presenter: presenter, panel: panel)
            }
        }
    }
}

// MARK: - Menu 悬浮层

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
        stealFocus(control)
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

        let anchorTrailing = anchor.position.column + max(anchor.size.width, 1)
        var column = anchorTrailing - panelSize.width
        if column < 0 { column = 0 }
        if column + panelSize.width > size.width {
            column = max(0, size.width - panelSize.width)
        }

        var line = anchor.position.line + max(anchor.size.height, 1)
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

// MARK: - Popover 悬浮层（相对锚点定位）

@MainActor
private struct PopoverFloatingLayer: View, PrimitiveView {
    let anchor: Rect
    let presenter: PopupPresenter
    let panel: AnyView

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: panel.view))
        let control = PopoverFloatingControl(anchor: anchor, presenter: presenter)
        control.panelControl = node.children[0].control(at: 0)
        control.addSubview(control.panelControl, at: 0)
        node.control = control
        stealFocus(control)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: panel.view)
        let control = node.control as! PopoverFloatingControl
        control.anchor = anchor
        control.presenter = presenter
        control.panelControl = node.children[0].control(at: 0)
        control.layer.invalidate()
    }
}

@MainActor
private final class PopoverFloatingControl: Control {
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
        let placeBelow = spaceBelow >= 3 || spaceBelow >= spaceAbove

        let maxHeight = max(Extended(2), placeBelow ? spaceBelow : spaceAbove)
        let measured = panelControl.size(
            proposedSize: Size(width: min(max(anchor.size.width + 10, 16), size.width), height: maxHeight)
        )
        let panelSize = Size(
            width: min(max(measured.width, 6), size.width),
            height: min(max(measured.height, 3), maxHeight)
        )
        panelControl.layout(size: panelSize)

        let anchorCenter = anchor.position.column + max(anchor.size.width, 1) / 2
        var column = anchorCenter - panelSize.width / 2
        if column < 0 { column = 0 }
        if column + panelSize.width > size.width {
            column = max(0, size.width - panelSize.width)
        }

        let line: Extended
        if placeBelow {
            line = anchor.position.line + max(anchor.size.height, 1)
        } else {
            line = max(0, anchor.position.line - panelSize.height)
        }

        panelControl.layer.frame.position = Position(column: column, line: line)
        presenter?.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        return panelControl?.hitTest(position: local)
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            presenter?.dismiss()
            return
        }
        super.handleKeyEvent(event)
    }
}

// MARK: - Modal（sheet / alert）

@MainActor
private struct ModalFloatingLayer: View, PrimitiveView {
    let presenter: PopupPresenter
    let panel: AnyView

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: panel.view))
        let control = ModalFloatingControl(presenter: presenter)
        control.panelControl = node.children[0].control(at: 0)
        control.addSubview(control.panelControl, at: 0)
        node.control = control
        stealFocus(control)
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: panel.view)
        let control = node.control as! ModalFloatingControl
        control.presenter = presenter
        control.panelControl = node.children[0].control(at: 0)
        control.layer.invalidate()
    }
}

@MainActor
private final class ModalFloatingControl: Control {
    weak var presenter: PopupPresenter?
    var panelControl: Control!

    init(presenter: PopupPresenter) {
        self.presenter = presenter
    }

    override var selectable: Bool { true }
    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelControl else { return }

        // 按内容固有尺寸居中，不把提案宽度强加给面板
        let maxW = max(Extended(8), size.width - 4)
        let maxH = max(Extended(3), size.height - 2)
        let measured = panelControl.size(proposedSize: Size(width: maxW, height: maxH))
        let panelSize = Size(
            width: min(max(measured.width, 1), maxW),
            height: min(max(measured.height, 1), maxH)
        )
        panelControl.layout(size: panelSize)
        let column = max(0, (size.width - panelSize.width) / 2)
        let line = max(0, (size.height - panelSize.height) / 2)
        panelControl.layer.frame.position = Position(column: column, line: line)
        presenter?.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {
        // 降低下层不透明度观感：只加 ANSI faint，不改前景/背景色
        for y in 0 ..< layer.frame.size.height.intValue {
            for x in 0 ..< layer.frame.size.width.intValue {
                let pos = Position(column: Extended(x), line: Extended(y))
                guard var cell = buffer.cell(at: pos) else { continue }
                if cell.char == "\0" { cell.char = " " }
                cell.attributes.faint = true
                // faint 与 bold 共用强度通道，关掉 bold 才能看出变淡
                cell.attributes.bold = false
                buffer.setCell(cell, at: pos)
            }
        }
    }

    /// 遮罩吞掉所有命中；面板上的交给子控件。
    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        if let hit = panelControl?.hitTest(position: local) {
            return hit
        }
        return self
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        if case .released(.left) = event.type {
            presenter?.dismiss()
        }
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            presenter?.dismiss()
            return
        }
        super.handleKeyEvent(event)
    }
}

// MARK: - Focus helper

@MainActor
private func stealFocus(_ control: Control) {
    DispatchQueue.main.async {
        guard let window = control.window else { return }
        window.firstResponder?.resignFirstResponder()
        window.firstResponder = control
        control.becomeFirstResponder()
    }
}

// MARK: - Chrome panels

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

@MainActor
struct SheetPanel<Content: View>: View {
    let content: Content

    var body: some View {
        ScrollView {
            content
        }
        .background(.default)
        .border(.rounded)
    }
}

@MainActor
struct AlertPanel<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .background(.default)
            .border(.rounded)
    }
}

@MainActor
struct PopoverPanel<Content: View>: View {
    let content: Content

    var body: some View {
        content
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
