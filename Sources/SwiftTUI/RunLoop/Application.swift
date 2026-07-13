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
        // 1049h 会清掉此前启用的鼠标模式；必须在备用屏之后再开 1003/1006，否则 move/onHover 要等焦点或点击才偶发恢复。
        await terminal.write("\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?7l\u{1B}[?1003h\u{1B}[?1006h")
        defer {
            let seq = "\u{1B}[?25h\u{1B}[?1003l\u{1B}[?1006l\u{1B}[?1049l\u{1B}[?7h"
            seq.withCString { _ = write(STDOUT_FILENO, $0, numericCast(strlen($0))) }
            renderer.stop()
            self.vtRenderer = nil
            self.renderer.vtRenderer = nil
        }
        
        updateWindowSize(size: terminal.size)
        control.layout(size: window.layer.frame.size)
        renderer.draw()
        try await update()

        isRunning = true
        defer { isRunning = false }
        
        let terminalInput = terminal.input
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: input loop — ends when stop() or stream finishes.
            group.addTask { [weak self] in
                do {
                    for try await event in terminalInput {
                        let isRunning = await self?.isRunning ?? false
                        if !isRunning { break }
                        await self?.handleTerminalEvent(event)
                        let stillRunning = await self?.isRunning ?? false
                        if !stillRunning { break }
                    }
                } catch is CancellationError {
                    // Task group cancelled after intentional stop — not a failure.
                }
            }
            
            // Task 2: rendering loop (DisplayLink)
            let link = VTDisplayLink(fps: 60) { [weak self] _ in
                let isRunning = await self?.isRunning ?? false
                // Exit the link loop; Application.start() treats this as normal shutdown.
                if !isRunning { throw CancellationError() }
                
                let scheduled = await self?.updateScheduled ?? false
                if scheduled {
                    try await self?.update()
                }
            }
            link.add(to: &group)
            
            // First finished child: intentional stop, input EOF, or real failure.
            let first = await group.nextResult()
            group.cancelAll()
            while let result = await group.nextResult() {
                if case .failure(let error) = result,
                   !(error is CancellationError),
                   isRunning
                {
                    throw error
                }
            }

            if case .failure(let error) = first {
                let stoppedIntentionally = !isRunning || error is CancellationError
                if !stoppedIntentionally {
                    throw error
                }
            }
        }
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

    @MainActor
    private func flushSwiftDataIfNeeded() {
        // Persist TUI-side edits; @Query refresh listens to ModelContext.didSave.
        if let context = swiftDataContext, context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    public func modelContainer(_ container: ModelContainer) -> Self {
        // Share mainContext with the rest of the app (CLI agents, DatabaseActor peers).
        // A fresh ModelContext only sees store data after another context saves — and the
        // old flush-based @Query path never noticed those foreign saves.
        let context = container.mainContext
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
                // 捕获期间也要刷新 hover，否则离开/释放后 onHover(false) 会丢
                window.setHoveredControl(control.hitTest(position: pos))
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

        // 含 target == nil（移出控件区域）→ leave
        window.setHoveredControl(target)

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
    private static let maxUpdateIterations = 4

    func update() async throws {
        // 重入时不能丢更新：`await present` 让出 MainActor 后 display link 可能再进这里。
        // 只标 schedule，让当前帧结束后的下一 tick 继续 drain。
        guard !isUpdating else {
            scheduleUpdate()
            return
        }
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

        // dismiss / Observation 可能在 update 中同步弄脏更多节点（OverlayHost 卸层）。
        // 必须在同一帧内继续 drain，否则 isPresented=false 后 sheet/popover 会卡住一帧甚至更久。
        var iterations = 0
        while iterations < Self.maxUpdateIterations {
            iterations += 1

            let nodes = invalidatedNodes
            invalidatedNodes = []
            let hasNodes = !nodes.isEmpty
            for node in nodes where node.isAttached(to: self) {
                node.update(using: node.view)
            }

            let presenter = window.popupPresenter
            let hadPanelRefresh = presenter?.needsPanelRefresh == true
            presenter?.refreshPresentedPanels()

            var layoutPasses = 0
            while needsLayout, layoutPasses < 4 {
                needsLayout = false
                control.invalidateSizeCache()
                control.layout(size: window.layer.frame.size)
                layoutPasses += 1
            }

            let needsAnother =
                !invalidatedNodes.isEmpty
                || needsLayout
                || presenter?.needsPanelRefresh == true
            if !hasNodes, !hadPanelRefresh, !needsAnother {
                break
            }
            if iterations == Self.maxUpdateIterations, needsAnother {
                scheduleUpdate()
            }
        }

        renderer.update()

        // Flush DB after rendering state changes (didSave drives @Query).
        flushSwiftDataIfNeeded()

        // Final presentation to VT
        if let vtRenderer = vtRenderer {
            let softCursor: VTPosition?
            if let absPos = window.firstResponder?.absoluteCursorPosition,
               absPos.line >= 0,
               absPos.column >= 0,
               absPos.line < window.layer.frame.size.height,
               absPos.column < window.layer.frame.size.width
            {
                softCursor = VTPosition(
                    row: absPos.line.intValue + 1,
                    column: absPos.column.intValue + 1
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
