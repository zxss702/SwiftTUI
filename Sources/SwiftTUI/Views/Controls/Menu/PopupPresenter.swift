import Foundation
import Observation

// MARK: - Kind

enum PopupKind: Equatable {
    case menu
    case sheet
    case popover
    case alert
}

// MARK: - Stack entry

/// 单层 present 记录。栈式叠加，便于 sheet / popover / alert / menu 嵌套与后续扩展。
@MainActor
final class PresentationRecord: Identifiable {
    let id: UUID
    let kind: PopupKind
    /// 每次刷新重建面板，保证 Binding / 嵌套 present 能随状态更新。
    var makePanel: () -> AnyView
    var anchor: Rect
    var panelFrame: Rect?
    let onDismiss: () -> Void
    /// 该层悬浮 Control，dismiss 后把焦点还给新的 top。
    weak var hostControl: Control?
    /// 悬浮层 Node，用于状态变化时原地刷新面板内容。
    weak var layerNode: Node?
    /// 发起 present 的视图节点；叠层挂在根 Overlay 上，需从此处继承 Environment。
    weak var environmentSource: Node?

    init(
        id: UUID = UUID(),
        kind: PopupKind,
        anchor: Rect,
        onDismiss: @escaping () -> Void,
        environmentSource: Node? = nil,
        makePanel: @escaping () -> AnyView
    ) {
        self.id = id
        self.kind = kind
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.environmentSource = environmentSource
        self.makePanel = makePanel
    }

    var panel: AnyView { makePanel() }

    var blocksUnderlyingHits: Bool {
        kind == .sheet || kind == .alert
    }
}

// MARK: - PopupPresenter

/// 应用级悬浮弹出层（**栈**）。新 present 压栈，不替换下层；`dismiss` 默认只弹顶层。
@Observable
@MainActor
public final class PopupPresenter {
    /// 从底到顶的 present 栈。
    private(set) var stack: [PresentationRecord] = []

    /// 应用状态变化后，在下一帧刷新栈内面板。
    @ObservationIgnored
    var needsPanelRefresh = false

    /// 顶层 id（兼容旧逻辑 / modifier session）。
    var presentationID: UUID? { stack.last?.id }

    var kind: PopupKind { stack.last?.kind ?? .menu }

    var panel: AnyView? { stack.last?.panel }

    var anchor: Rect {
        get { stack.last?.anchor ?? .zero }
        set { stack.last?.anchor = newValue }
    }

    var panelFrame: Rect? {
        get { stack.last?.panelFrame }
        set { stack.last?.panelFrame = newValue }
    }

    public var isPresented: Bool { !stack.isEmpty }

    /// 顶层是否吞掉下层命中（sheet / alert）。
    var blocksUnderlyingHits: Bool {
        stack.last?.blocksUnderlyingHits ?? false
    }

    var top: PresentationRecord? { stack.last }

    func contains(_ id: UUID) -> Bool {
        stack.contains { $0.id == id }
    }

    func record(id: UUID) -> PresentationRecord? {
        stack.first { $0.id == id }
    }

    /// 用最新内容闭包替换已 present 层的 `makePanel`（宿主 modifier 每次 sync 时调用）。
    /// 不在这里置 `needsPanelRefresh`：调用方一定在节点 update 路径上，`invalidateNode` 已标记刷新。
    func updateMakePanel(id: UUID, makePanel: @escaping () -> AnyView) {
        guard let record = record(id: id) else { return }
        record.makePanel = makePanel
    }

    /// 由 Application 在节点失效时标记；update 循环末尾调用 `refreshPresentedPanels`。
    func noteContentInvalidated() {
        guard !stack.isEmpty else { return }
        needsPanelRefresh = true
    }

    /// 用最新 `makePanel()` 刷新已 present 的内容（嵌套 sheet 的 Binding 依赖此路径）。
    func refreshPresentedPanels() {
        guard needsPanelRefresh else { return }
        needsPanelRefresh = false
        // 按 id 快照；刷新过程中嵌套 sync 可能 dismiss 上层/本层，避免更新已出栈的残留 layer。
        let ids = stack.map(\.id)
        for id in ids {
            guard let record = record(id: id), let node = record.layerNode else { continue }
            node.update(using: node.view)
        }
    }

    // MARK: - Menu（现有）

    @discardableResult
    func present<V: View>(
        anchor: Rect,
        environmentSource: Node? = nil,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> V
    ) -> UUID {
        let id = UUID()
        return push(
            id: id,
            kind: .menu,
            anchor: anchor,
            onDismiss: onDismiss,
            environmentSource: environmentSource,
            makePanel: { [weak self] in
                AnyView(
                    PopupMenuPanel(content: content())
                        .environment(\.dismiss, DismissAction { self?.dismiss(id: id) })
                        .environment(\.buttonDismissesPresentation, true)
                )
            }
        )
    }

    /// 无明确锚点时，居中偏上显示（菜单样式）。
    @discardableResult
    func presentCentered<V: View>(
        environmentSource: Node? = nil,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> V
    ) -> UUID {
        present(
            anchor: Rect(position: Position(column: 2, line: 2), size: Size(width: 1, height: 1)),
            environmentSource: environmentSource,
            onDismiss: onDismiss,
            content: content
        )
    }

    // MARK: - Sheet / Popover / Alert

    @discardableResult
    func presentSheet<V: View>(
        environmentSource: Node? = nil,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> V
    ) -> UUID {
        let id = UUID()
        return push(
            id: id,
            kind: .sheet,
            anchor: .zero,
            onDismiss: onDismiss,
            environmentSource: environmentSource,
            makePanel: { [weak self] in
                AnyView(SheetPanel(content: content().environment(\.dismiss, DismissAction {
                    self?.dismiss(id: id)
                })))
            }
        )
    }

    @discardableResult
    func presentPopover<V: View>(
        anchor: Rect,
        environmentSource: Node? = nil,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> V
    ) -> UUID {
        let id = UUID()
        return push(
            id: id,
            kind: .popover,
            anchor: anchor,
            onDismiss: onDismiss,
            environmentSource: environmentSource,
            makePanel: { [weak self] in
                AnyView(PopoverPanel(content: content().environment(\.dismiss, DismissAction {
                    self?.dismiss(id: id)
                })))
            }
        )
    }

    @discardableResult
    func presentAlert<V: View>(
        environmentSource: Node? = nil,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> V
    ) -> UUID {
        let id = UUID()
        return push(
            id: id,
            kind: .alert,
            anchor: .zero,
            onDismiss: onDismiss,
            environmentSource: environmentSource,
            makePanel: { [weak self] in
                AnyView(
                    AlertPanel(content: content())
                        .environment(\.dismiss, DismissAction { self?.dismiss(id: id) })
                        .environment(\.buttonDismissesPresentation, true)
                )
            }
        )
    }

    /// 关闭顶层。
    public func dismiss() {
        guard let top else { return }
        dismiss(id: top.id)
    }

    /// 关闭指定层，并一并关闭其上所有层（父级关闭时子 present 跟着走）。
    public func dismiss(id: UUID) {
        guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
        let removed = Array(stack[index...])
        let window = removed.lazy.reversed().compactMap(\.hostControl?.window).first
            ?? stack.first?.hostControl?.window
        stack.removeSubrange(index...)
        for record in removed.reversed() {
            record.onDismiss()
        }
        restoreFocus(afterDismissToWindow: window)
    }

    /// 清空整栈。
    public func dismissAll() {
        guard !stack.isEmpty else { return }
        let removed = stack
        let window = removed.lazy.reversed().compactMap(\.hostControl?.window).first
        stack = []
        for record in removed.reversed() {
            record.onDismiss()
        }
        restoreFocus(afterDismissToWindow: window)
    }

    // MARK: - Private

    @discardableResult
    private func push(
        id: UUID = UUID(),
        kind: PopupKind,
        anchor: Rect,
        onDismiss: @escaping () -> Void,
        environmentSource: Node? = nil,
        makePanel: @escaping () -> AnyView
    ) -> UUID {
        // 菜单：同级再开时先收起顶层菜单，避免菜单叠菜单；模态/popover 允许嵌套。
        if kind == .menu, let top, top.kind == .menu {
            dismiss(id: top.id)
        }
        let record = PresentationRecord(
            id: id,
            kind: kind,
            anchor: anchor,
            onDismiss: onDismiss,
            environmentSource: environmentSource,
            makePanel: makePanel
        )
        stack.append(record)
        return id
    }

    private func restoreFocus(afterDismissToWindow window: Window?) {
        if let control = stack.last?.hostControl {
            stealFocus(control)
            return
        }
        // 栈空时必须把焦点还给主界面；否则 firstResponder 仍停在已卸下的 sheet 控件上。
        DispatchQueue.main.async {
            guard let window else { return }
            window.setFirstResponder(window.controls.first?.firstSelectableElement)
        }
    }
}

// MARK: - Overlay host

@MainActor
struct PopupOverlayHost: View {
    @Environment(PopupPresenter.self) private var presenter

    var body: some View {
        let _ = presenter.stack.map(\.id)
        ZStack(alignment: .topLeading) {
            ForEach(presenter.stack) { entry in
                PresentationChrome(entry: entry, presenter: presenter)
            }
        }
    }
}

/// 按 kind 分发具体悬浮层；新增 kind 时只扩这里。
@MainActor
private struct PresentationChrome: View {
    let entry: PresentationRecord
    let presenter: PopupPresenter

    var body: some View {
        switch entry.kind {
        case .menu:
            FloatingPopupLayer(entry: entry, presenter: presenter)
        case .popover:
            PopoverFloatingLayer(entry: entry, presenter: presenter)
        case .sheet, .alert:
            ModalFloatingLayer(entry: entry, presenter: presenter)
        }
    }
}

// MARK: - Panel attach helper

/// 叠层挂在根 `PopupOverlayHost` 下，默认只有根上的 `PopupPresenter`。
/// 把发起方节点上的 Environment（NavigationContext、业务 Observable 等）注入叠层节点。
@MainActor
private func installInheritedEnvironment(on node: Node, from source: Node?) {
    guard let source else {
        node.environment = nil
        return
    }
    node.environment = { [weak source] env in
        guard let source else { return }
        let inherited = NavigationEnvironment.values(from: source)
        for (key, value) in inherited.values {
            env.values[key] = value
        }
    }
}

@MainActor
private func attachPanel(to host: Control, panel: Control, stored: inout Control!) {
    if stored === panel, host.children.contains(where: { $0 === panel }) {
        return
    }
    if let stored, let index = host.children.firstIndex(where: { $0 === stored }) {
        host.removeSubview(at: index)
    } else {
        while !host.children.isEmpty {
            host.removeSubview(at: 0)
        }
    }
    stored = panel
    host.addSubview(panel, at: 0)
}

// MARK: - Menu 悬浮层

@MainActor
private struct FloatingPopupLayer: View, PrimitiveView {
    let entry: PresentationRecord
    let presenter: PopupPresenter

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        entry.layerNode = node
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.addNode(at: 0, Node(view: entry.makePanel().view))
        let control = FloatingPopupControl(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        node.control = control
        stealFocus(control)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.control as! FloatingPopupControl
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        control.layer.invalidate()
    }
}

@MainActor
private final class FloatingPopupControl: Control {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelControl: Control!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    override var selectable: Bool { true }

    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelControl else { return }
        let anchor = entry.anchor

        let spaceBelow = max(Extended(1), size.height - (anchor.position.line + max(anchor.size.height, 1)))
        let spaceAbove = max(Extended(1), anchor.position.line)
        let maxHeight = max(spaceBelow, spaceAbove)

        let measured = panelControl.size(
            proposedSize: Size(width: max(anchor.size.width + 8, 24), height: .infinity)
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
        entry.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        guard let panelControl else { return nil }
        return panelControl.hitTest(position: local)
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            guard presenter?.top?.id == entry.id else { return }
            presenter?.dismiss(id: entry.id)
            return
        }
        super.handleKeyEvent(event)
    }
}

// MARK: - Popover 悬浮层（相对锚点定位）

@MainActor
private struct PopoverFloatingLayer: View, PrimitiveView {
    let entry: PresentationRecord
    let presenter: PopupPresenter

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        entry.layerNode = node
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.addNode(at: 0, Node(view: entry.makePanel().view))
        let control = PopoverFloatingControl(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        node.control = control
        stealFocus(control)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.control as! PopoverFloatingControl
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        control.layer.invalidate()
    }
}

@MainActor
private final class PopoverFloatingControl: Control {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelControl: Control!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    override var selectable: Bool { true }
    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelControl else { return }
        let anchor = entry.anchor

        let spaceBelow = max(Extended(0), size.height - (anchor.position.line + max(anchor.size.height, 1)))
        let spaceAbove = max(Extended(0), anchor.position.line)
        let spaceTrailing = max(Extended(0), size.width - (anchor.position.column + max(anchor.size.width, 1)))
        let spaceLeading = max(Extended(0), anchor.position.column)

        // 先按「尽量大」测固有尺寸，再按四边空间选型
        let measured = panelControl.size(
            proposedSize: Size(
                width: max(Extended(6), size.width),
                height: .infinity
            )
        )
        let ideal = Size(
            width: min(max(measured.width, 6), size.width),
            height: min(max(measured.height, 2), size.height)
        )

        enum Placement { case below, above, trailing, leading }
        let candidates: [(Placement, Extended, Bool)] = [
            (.below, spaceBelow, spaceBelow >= ideal.height),
            (.above, spaceAbove, spaceAbove >= ideal.height),
            (.trailing, spaceTrailing, spaceTrailing >= ideal.width),
            (.leading, spaceLeading, spaceLeading >= ideal.width),
        ]
        let placement: Placement
        if let bestFit = candidates.filter(\.2).max(by: { $0.1 < $1.1 }) {
            placement = bestFit.0
        } else if let best = candidates.max(by: { $0.1 < $1.1 }) {
            placement = best.0
        } else {
            placement = .below
        }

        let panelSize: Size
        switch placement {
        case .below, .above:
            panelSize = Size(
                width: ideal.width,
                height: min(ideal.height, max(Extended(2), placement == .below ? spaceBelow : spaceAbove))
            )
        case .trailing, .leading:
            panelSize = Size(
                width: min(ideal.width, max(Extended(6), placement == .trailing ? spaceTrailing : spaceLeading)),
                height: ideal.height
            )
        }
        panelControl.layout(size: panelSize)

        let anchorCenterX = anchor.position.column + max(anchor.size.width, 1) / 2
        let anchorCenterY = anchor.position.line + max(anchor.size.height, 1) / 2
        var column: Extended
        var line: Extended
        switch placement {
        case .below:
            column = anchorCenterX - panelSize.width / 2
            line = anchor.position.line + max(anchor.size.height, 1)
        case .above:
            column = anchorCenterX - panelSize.width / 2
            line = anchor.position.line - panelSize.height
        case .trailing:
            column = anchor.position.column + max(anchor.size.width, 1)
            line = anchorCenterY - panelSize.height / 2
        case .leading:
            column = anchor.position.column - panelSize.width
            line = anchorCenterY - panelSize.height / 2
        }
        if column < 0 { column = 0 }
        if column + panelSize.width > size.width {
            column = max(0, size.width - panelSize.width)
        }
        if line < 0 { line = 0 }
        if line + panelSize.height > size.height {
            line = max(0, size.height - panelSize.height)
        }

        panelControl.layer.frame.position = Position(column: column, line: line)
        entry.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        return panelControl?.hitTest(position: local)
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            guard presenter?.top?.id == entry.id else { return }
            presenter?.dismiss(id: entry.id)
            return
        }
        super.handleKeyEvent(event)
    }
}

// MARK: - Modal（sheet / alert）

@MainActor
private struct ModalFloatingLayer: View, PrimitiveView {
    let entry: PresentationRecord
    let presenter: PopupPresenter

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        entry.layerNode = node
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.addNode(at: 0, Node(view: entry.makePanel().view))
        let control = ModalFloatingControl(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        node.control = control
        stealFocus(control)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.control as! ModalFloatingControl
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].control(at: 0), stored: &control.panelControl)
        entry.hostControl = control
        control.layer.invalidate()
    }
}

@MainActor
private final class ModalFloatingControl: Control {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelControl: Control!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    override var selectable: Bool { true }
    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelControl else { return }

        let maxW = max(Extended(8), size.width - 4)
        let maxH = max(Extended(3), size.height - 2)
        let measured = panelControl.size(proposedSize: Size(width: maxW, height: .infinity))
        let panelSize = Size(
            width: min(max(measured.width, 1), maxW),
            height: min(max(measured.height, 1), maxH)
        )
        panelControl.layout(size: panelSize)
        let column = max(0, (size.width - panelSize.width) / 2)
        let line = max(0, (size.height - panelSize.height) / 2)
        panelControl.layer.frame.position = Position(column: column, line: line)
        entry.panelFrame = Rect(position: panelControl.layer.frame.position, size: panelSize)
    }

    override func draw(into buffer: inout ScreenBuffer) {
        // 降低下层不透明度观感：只加 ANSI faint，不改前景/背景色
        for y in 0 ..< layer.frame.size.height.intValue {
            for x in 0 ..< layer.frame.size.width.intValue {
                let pos = Position(column: Extended(x), line: Extended(y))
                guard var cell = buffer.cell(at: pos) else { continue }
                if cell.char == "\0" { cell.char = " " }
                cell.attributes.faint = true
                cell.attributes.bold = false
                buffer.setCell(cell, at: pos)
            }
        }
    }

    override func hitTest(position: Position) -> Control? {
        let local = position - layer.frame.position
        if let hit = panelControl?.hitTest(position: local) {
            return hit
        }
        return self
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        if case .released(.left) = event.type {
            // 仅顶层遮罩响应外点关闭，避免嵌套时误关下层
            guard presenter?.top?.id == entry.id else { return }
            presenter?.dismiss(id: entry.id)
        }
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        if event.keycode == VTKeyCode.escape || event.character == "\u{1b}" {
            guard presenter?.top?.id == entry.id else { return }
            presenter?.dismiss(id: entry.id)
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
        let target = control.canReceiveFocus ? control : (control.firstSelectableElement ?? control)
        window.setFirstResponder(target)
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

// MARK: - 触发按钮（回调绝对 frame + 自身 Node，便于叠层继承 Environment）

@MainActor
struct PopupAnchorButton<Label: View>: View, PrimitiveView {
    let label: Label
    let action: (Rect, Node) -> Void

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: VStack(content: label).view))
        let control = PopupAnchorButtonControl { [weak node] anchor in
            guard let node else { return }
            action(anchor, node)
        }
        control.label = node.children[0].control(at: 0)
        control.addSubview(control.label, at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: VStack(content: label).view)
        (node.control as! PopupAnchorButtonControl).action = { [weak node] anchor in
            guard let node else { return }
            action(anchor, node)
        }
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
