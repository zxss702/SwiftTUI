import Foundation



@MainActor
public class Application {
    private let node: Node
    let window: Window
    private let control: Control
    private let renderer: Renderer
    private var vtRenderer: VTRenderer?

    private var invalidatedNodes: [Node] = []
    private var updateScheduled = false
    private var isPresenting = false
    private var pendingResizeSize: Size?
    private var isRunning = false
    private var needsLayout = true

    public init<I: View>(rootView: I) {
        let popupPresenter = PopupPresenter()
        // 根必须是带 control 的 LayoutRoot（ZStack）；不要用 .environment 包一层，
        // 否则 SetEnvironmentObject 没有 control，这里会 unwrap 崩溃。
        node = Node(
            view: ZStack(alignment: .center) {
                rootView
                PopupOverlayHost()
            }.view
        )
        // PopupOverlayHost 在 build 时就会读 @Environment(PopupPresenter.self)，必须先注入
        node.environment = { env in
            env[PopupPresenter.self] = popupPresenter
        }
        node.build()

        control = node.control!

        window = Window()
        window.popupPresenter = popupPresenter
        window.addControl(control)

        window.setFirstResponder(control.firstSelectableElement)
        
        renderer = Renderer(layer: window.layer)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self

        // dismiss 注入根环境
        let oldEnv = self.node.environment
        self.node.environment = { [weak self] env in
            oldEnv?(&env)
            env.dismiss = DismissAction {
                self?.stop()
            }
        }
    }

    public func start() async throws {
        let vtRenderer = try await VTRenderer(mode: .raw)
        self.vtRenderer = vtRenderer
        self.renderer.vtRenderer = vtRenderer
        
        let terminal = vtRenderer.terminal
        await terminal.write("\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?7l")
        defer {
            let seq = "\u{1B}[?25h\u{1B}[?1049l\u{1B}[?7h"
            seq.withCString { _ = write(STDOUT_FILENO, $0, numericCast(strlen($0))) }
            renderer.stop()
        }
        
        updateWindowSize(size: terminal.size)
        control.layout(size: window.layer.frame.size)
        renderer.draw()
        try await update()

        isRunning = true
        
        let terminalInput = terminal.input
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: input loop
            group.addTask { [weak self] in
                for try await event in terminalInput {
                    let isRunning = await self?.isRunning ?? false
                    if !isRunning { break }
                    await self?.handleTerminalEvent(event)
                    let stillRunning = await self?.isRunning ?? false
                    if !stillRunning { break }
                }
            }
            
            // Task 2: rendering loop (DisplayLink)
            let link = VTDisplayLink(fps: 60) { [weak self] _ in
                let isRunning = await self?.isRunning ?? false
                if !isRunning { throw CancellationError() }
                
                let scheduled = await self?.updateScheduled ?? false
                if scheduled {
                    try await self?.update()
                }
            }
            link.add(to: &group)
            
            try await group.next()
            group.cancelAll()
        }
        
        // Reset terminal on exit
        self.vtRenderer = nil
        self.renderer.vtRenderer = nil
    }

    @MainActor
    private func handleTerminalEvent(_ event: VTEvent) {
        switch event {
        case .resize(let resizeEvent):
            self.handleWindowSizeChange(size: resizeEvent.size)
        case .key(let keyEvent):
            self.handleKeyInput(keyEvent)
        case .mouse(let mouseEvent):
            self.handleMouseInput(mouseEvent)
        }
    }
    var swiftDataContext: ModelContext?
    #if canImport(SwiftData)
    var swiftDataObservers: [() -> Void] = []
    #endif

    @MainActor
    private func flushSwiftDataIfNeeded() {
        if let context = swiftDataContext {
            if context.hasChanges {
                try? context.save()
                #if canImport(SwiftData)
                for observer in swiftDataObservers {
                    observer()
                }
                #endif
            }
        }
    }

    @MainActor
    public func modelContainer(_ container: ModelContainer) -> Self {
        let context = ModelContext(container)
        self.swiftDataContext = context
        
        let oldEnv = self.node.environment
        self.node.environment = { env in
            oldEnv?(&env)
            env.modelContext = context
        }
        self.invalidateNode(self.node)
        return self
    }

    func handleKeyInput(_ event: KeyEvent) {
        if (event.character == "c" && event.modifiers.contains(.ctrl)) || event.character == "\u{03}" {
            stop()
            return
        } 
        
        #if DEBUG
        if event.character == "D" {
            dumpTree()
            return
        }
        #endif
        
        window.firstResponder?.handleKeyEvent(event)
    }

    private var hoveredControl: Control?

    private func handleMouseInput(_ event: MouseEvent) {
        let pos = event.position

        // 拖动手势捕获：move/release 交给按下时的控件
        if let capture = window.mouseCapture {
            switch event.type {
            case .move, .released:
                capture.handleMouseEvent(event)
                if case .released = event.type {
                    window.mouseCapture = nil
                }
                return
            default:
                break
            }
        }

        let target = control.hitTest(position: pos)

        // 外点关闭：menu/popover 先把事件交给下层再 dismiss；sheet/alert 由遮罩自己处理
        let shouldDismissPopup: Bool = {
            guard let presenter = window.popupPresenter, presenter.isPresented else { return false }
            if presenter.blocksUnderlyingHits { return false }
            guard let frame = presenter.panelFrame else { return false }
            switch event.type {
            case .released(.left), .released(.right):
                return !frame.contains(pos)
            default:
                return false
            }
        }()

        if target !== hoveredControl {
            hoveredControl?.isHovered = false
            target?.isHovered = true
            hoveredControl = target
        }

        if let target = target {
            target.handleMouseEvent(event)
            if case .pressed(.left) = event.type, target.canReceiveFocus {
                window.setFirstResponder(target)
            }
        }

        if shouldDismissPopup {
            window.popupPresenter?.dismiss()
        }
    }

    /// Marks a node for content rebuild. Does **not** force a full-tree layout by default —
    /// layout is requested separately when structure or measured size actually changes.
    func invalidateNode(_ node: Node, layout: Bool = false) {
        // 条件分支 / NavigationPage 切走后 removeNode 会把子树 parent 置 nil。
        // Observation 仍可能回调这些已卸下的节点；若继续 update，@Environment 会沿空父链
        // 找不到 NavigationContext 等对象。根节点 parent == nil 但 application != nil。
        guard node.isAttached(to: self) else { return }

        if !invalidatedNodes.contains(where: { $0 === node }) {
            invalidatedNodes.append(node)
            scheduleUpdate()
        }
        if layout {
            needsLayout = true
        }
        // 已 present 的面板是快照树外的节点；状态变化时刷新栈内内容（嵌套 sheet 等）
        window.popupPresenter?.noteContentInvalidated()
    }

    /// Request a full control-tree layout on the next update pass.
    func requestLayout() {
        needsLayout = true
        scheduleUpdate()
    }

    func scheduleUpdate() {
        updateScheduled = true
    }

    private var isUpdating = false

    func update() async throws {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        updateScheduled = false

        if let size = pendingResizeSize {
            pendingResizeSize = nil
            window.layer.frame.size = size
            vtRenderer?.resize(to: size)
            control.layer.invalidate()
            needsLayout = true
        }

        let nodes = invalidatedNodes
        invalidatedNodes = []
        for node in nodes where node.isAttached(to: self) {
            node.update(using: node.view)
        }

        // 刷新 present 面板（嵌套 sheet 等依赖 Binding 的内容）
        window.popupPresenter?.refreshPresentedPanels()

        // Layout may request another pass (e.g. structural change during GeometryReader sync).
        var layoutPasses = 0
        while needsLayout, layoutPasses < 4 {
            needsLayout = false
            control.layout(size: window.layer.frame.size)
            layoutPasses += 1
        }

        renderer.update()
        
        #if canImport(SwiftData)
        // Flush DB after rendering state changes
        flushSwiftDataIfNeeded()
        #endif
        
        // Final presentation to VT
        if let vtRenderer = vtRenderer {
            let softCursor: VTPosition?
            if let responder = window.firstResponder, let cursor = responder.cursorPosition {
                let absPos = responder.absoluteFrame.position
                softCursor = VTPosition(
                    row: absPos.line.intValue + cursor.line.intValue + 1,
                    column: absPos.column.intValue + cursor.column.intValue + 1
                )
            } else {
                softCursor = nil
            }
            isPresenting = true
            await vtRenderer.present(cursor: softCursor)
            isPresenting = false
        }
    }

    private func handleWindowSizeChange(size: Size) {
        pendingResizeSize = size
        scheduleUpdate()
    }

    func updateWindowSize(size: Size) {
        window.layer.frame.size = size
    }

    private func stop() {
        isRunning = false
    }
}
