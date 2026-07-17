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
    /// Cached during host `layout` — can be stale: root `ZStack(.center)` still
    /// holds the previous overlay offset while children layout. Prefer
    /// ``resolvedPanelFrame`` / `PopupPresenter.panelFrame` (live absolute).
    var panelFrame: Rect?
    /// Panel root element; used for a live absolute frame after parent positions settle.
    weak var panelElement: Element?
    let onDismiss: () -> Void
    /// 该层悬浮 Element，dismiss 后把焦点还给新的 top。
    weak var hostElement: Element?
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

    /// Live panel bounds in window space (see `PopupPresenter.panelFrame`).
    var resolvedPanelFrame: Rect? {
        panelElement?.absoluteFrame ?? panelFrame
    }

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

    /// First responder before the first present stole focus; restored when the stack empties.
    @ObservationIgnored
    weak var focusBeforePresentation: Element?

    /// Host window — set by `Application` so focus steals work before the
    /// floating host Element is parented into the tree (`control.window` is
    /// still nil during `buildNode`).
    @ObservationIgnored
    weak var hostWindow: Window?

    /// 顶层 id（兼容旧逻辑 / modifier session）。
    var presentationID: UUID? { stack.last?.id }

    var kind: PopupKind { stack.last?.kind ?? .menu }

    var panel: AnyView? { stack.last?.panel }

    var anchor: Rect {
        get { stack.last?.anchor ?? .zero }
        set { stack.last?.anchor = newValue }
    }

    /// Window-absolute panel bounds for hit-testing / outside-dismiss.
    /// Always derived from the live element tree when `panelElement` is set —
    /// a frame cached mid-layout is wrong while ancestors still have the
    /// previous centered overlay offset (item at ~16,9 vs stale ~35,16).
    var panelFrame: Rect? {
        get { stack.last?.resolvedPanelFrame }
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
    func updateMakePanel(id: UUID, makePanel: @escaping () -> AnyView) {
        guard let record = record(id: id) else { return }
        record.makePanel = makePanel
        // Same settle as host update — do not wait for a later invalidate.
        needsPanelRefresh = true
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
        let window = removed.lazy.reversed().compactMap(\.hostElement?.window).first
            ?? stack.first?.hostElement?.window
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
        let window = removed.lazy.reversed().compactMap(\.hostElement?.window).first
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
        if let control = stack.last?.hostElement {
            stealFocus(control, presenter: self)
            return
        }
        // 栈空：优先还给 present 前的焦点（例如 TextEditor），避免总是跳到第一个 Button。
        guard let window else {
            focusBeforePresentation = nil
            return
        }
        let restored = focusBeforePresentation
        focusBeforePresentation = nil
        if let clock = window.layer.rootRenderer?.application?.clock {
            clock.scheduleNextTurn {
                if let restored, restored.window === window, restored.canReceiveFocus {
                    window.setFirstResponder(restored)
                } else {
                    window.setFirstResponder(window.elements.first?.firstSelectableElement)
                }
            }
        } else if let restored, restored.window === window, restored.canReceiveFocus {
            window.setFirstResponder(restored)
        } else {
            window.setFirstResponder(window.elements.first?.firstSelectableElement)
        }
    }
}

// MARK: - Overlay host

@MainActor
struct PopupOverlayHost: View {
    @Environment(PopupPresenter.self) private var presenter

    var body: some View {
        let _ = presenter.stack.map(\.id)
        // Pass through misses: a presented menu sizes this ZStack to the window;
        // default Element.hitTest returns `self` when children miss, which ate
        // every click outside the panel ("first click works, then dead").
        ZStack(alignment: .topLeading) {
            ForEach(presenter.stack) { entry in
                PresentationChrome(entry: entry, presenter: presenter)
            }
        }
        // Window-sized ZStack must not absorb misses (otherwise Menu item /
        // label clicks become `ZStackElement` with `pointer: nil`).
        .hitTestPassthrough()
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
private func attachPanel(to host: Element, panel: Element, stored: inout Element!) {
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
        let control = FloatingPopupElement(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        node.element = control
        stealFocus(control, presenter: presenter)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.element as! FloatingPopupElement
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        control.layer.invalidate()
    }
}

@MainActor
private final class FloatingPopupElement: Element {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelElement: Element!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    /// Presentation chrome is not a text first-responder; Escape is routed by
    /// `Application` while presented.
    override var selectable: Bool { false }

    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelElement else { return }
        let anchor = entry.anchor

        let spaceBelow = max(Extended(1), size.height - (anchor.position.line + max(anchor.size.height, 1)))
        let spaceAbove = max(Extended(1), anchor.position.line)
        let maxHeight = max(spaceBelow, spaceAbove)

        let measured = panelElement.size(
            proposedSize: Size(width: max(anchor.size.width + 8, 24), height: .infinity)
        )
        let panelSize = Size(
            width: min(max(measured.width, 8), size.width),
            height: min(max(measured.height, 1), maxHeight)
        )
        panelElement.layout(size: panelSize)

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
        panelElement.layer.frame.position = Position(column: column, line: line)
        // Window-absolute frame for Application.inPanel / hitTestPointer.
        entry.panelFrame = panelElement.absoluteFrame
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    override func hitTest(position: Position) -> Element? {
        // `position` is in parent-local coords (same as Element.hitTest).
        guard let panelElement else { return nil }
        return panelElement.hitTest(position: position - layer.frame.position)
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
        let control = PopoverFloatingElement(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        node.element = control
        stealFocus(control, presenter: presenter)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.element as! PopoverFloatingElement
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        control.layer.invalidate()
    }
}

@MainActor
private final class PopoverFloatingElement: Element {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelElement: Element!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    override var selectable: Bool { false }
    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelElement else { return }
        let anchor = entry.anchor

        let spaceBelow = max(Extended(0), size.height - (anchor.position.line + max(anchor.size.height, 1)))
        let spaceAbove = max(Extended(0), anchor.position.line)
        let spaceTrailing = max(Extended(0), size.width - (anchor.position.column + max(anchor.size.width, 1)))
        let spaceLeading = max(Extended(0), anchor.position.column)

        // 先按「尽量大」测固有尺寸，再按四边空间选型
        let measured = panelElement.size(
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
        panelElement.layout(size: panelSize)

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

        panelElement.layer.frame.position = Position(column: column, line: line)
        entry.panelFrame = panelElement.absoluteFrame
    }

    override func draw(into buffer: inout ScreenBuffer) {}

    override func hitTest(position: Position) -> Element? {
        let local = position - layer.frame.position
        return panelElement?.hitTest(position: local)
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
        let control = ModalFloatingElement(entry: entry, presenter: presenter)
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        node.element = control
        stealFocus(control, presenter: presenter)
    }

    func updateNode(_ node: Node) {
        entry.layerNode = node
        node.view = self
        installInheritedEnvironment(on: node, from: entry.environmentSource)
        node.children[0].update(using: entry.makePanel().view)
        let control = node.element as! ModalFloatingElement
        control.entry = entry
        control.presenter = presenter
        attachPanel(to: control, panel: node.children[0].element(at: 0), stored: &control.panelElement)
        entry.panelElement = control.panelElement
        entry.hostElement = control
        control.layer.invalidate()
    }
}

@MainActor
private final class ModalFloatingElement: Element {
    var entry: PresentationRecord
    weak var presenter: PopupPresenter?
    var panelElement: Element!

    init(entry: PresentationRecord, presenter: PopupPresenter) {
        self.entry = entry
        self.presenter = presenter
    }

    override var selectable: Bool { false }
    override func size(proposedSize: Size) -> Size { proposedSize }

    override func layout(size: Size) {
        super.layout(size: size)
        guard let panelElement else { return }

        let maxW = max(Extended(8), size.width - 4)
        let maxH = max(Extended(3), size.height - 2)
        let measured = panelElement.size(proposedSize: Size(width: maxW, height: .infinity))
        let panelSize = Size(
            width: min(max(measured.width, 1), maxW),
            height: min(max(measured.height, 1), maxH)
        )
        panelElement.layout(size: panelSize)
        let column = max(0, (size.width - panelSize.width) / 2)
        let line = max(0, (size.height - panelSize.height) / 2)
        panelElement.layer.frame.position = Position(column: column, line: line)
        entry.panelFrame = panelElement.absoluteFrame
    }

    override func draw(into buffer: inout ScreenBuffer) {
        // Dim underlying UI in place — never overwrite glyphs with spaces
        // (that wiped the root view and made sheets look like a blank wall).
        let panel = entry.resolvedPanelFrame
        let origin = layer.frame.position
        for y in 0 ..< layer.frame.size.height.intValue {
            for x in 0 ..< layer.frame.size.width.intValue {
                let abs = Position(
                    column: origin.column + Extended(x),
                    line: origin.line + Extended(y)
                )
                if let panel, panel.contains(abs) { continue }
                buffer.dimCell(at: Position(column: Extended(x), line: Extended(y)))
            }
        }
    }

    override func hitTest(position: Position) -> Element? {
        let local = position - layer.frame.position
        if let hit = panelElement?.hitTest(position: local) {
            return hit
        }
        return self
    }

    override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
        // Scrim / outside-panel: dismiss on gesture end (UIKit-style).
        guard event.button == .left else { return false }
        switch event.phase {
        case .began, .moved:
            return true
        case .ended:
            guard presenter?.top?.id == entry.id else { return false }
            presenter?.dismiss(id: entry.id)
            return true
        case .cancelled:
            return true
        }
    }

    override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
        false
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
private func stealFocus(_ control: Element, presenter: PopupPresenter) {
    // Prefer the live window; fall back to presenter's host while the floating
    // element is still being parented (`control.window` is nil in `buildNode`).
    guard let window = control.window ?? presenter.hostWindow else { return }

    // Remember pre-presentation text focus once per stack life. Presentation
    // chrome itself is never firstResponder (SwiftUI-shaped: only text inputs).
    if presenter.focusBeforePresentation == nil,
       let fr = window.firstResponder,
       fr.canReceiveFocus,
       !fr.isDescendant(of: control)
    {
        presenter.focusBeforePresentation = fr
    }
    // Move focus only when the sheet/popover contains a text field; menus leave
    // FR alone (Application routes Escape / keys to the host while open).
    let apply: @MainActor () -> Void = {
        if let textInput = control.firstSelectableElement {
            window.setFirstResponder(textInput)
            return
        }
        // Sheet / alert dim the underlay — drop the soft caret even when nothing
        // inside the panel claims focus (restore via focusBeforePresentation).
        guard presenter.top?.hostElement === control,
              presenter.blocksUnderlyingHits,
              window.firstResponder != nil
        else { return }
        window.setFirstResponder(nil)
    }
    if let clock = window.layer.rootRenderer?.application?.clock {
        clock.scheduleNextTurn(apply)
    } else {
        apply()
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

