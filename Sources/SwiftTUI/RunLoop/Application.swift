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
        for try await event in terminal.input {
            if !isRunning { break }
            let isScroll: Bool
            switch event {
            case .resize(let resizeEvent):
                handleWindowSizeChange(size: resizeEvent.size)
                isScroll = false
            case .key(let keyEvent):
                handleKeyInput(keyEvent)
                isScroll = false
            case .mouse(let mouseEvent):
                handleMouseInput(mouseEvent)
                if case .scroll = mouseEvent.type { isScroll = true } else { isScroll = false }
            }
            if !isRunning { break }
            
            // 键鼠与滚动都立刻刷新：否则 Binding/@State 要等下一次输入才上屏
            //（POSIX 上 scheduleUpdate 的 Task 会被 input await 饿死）。
            if updateScheduled || isScroll {
                try? await update()
            }
            
            #if canImport(SwiftData)
            // macOS SwiftData relies on CFRunLoop to autosave and post notifications.
            // Since we use an AsyncStream event loop, we manually check and save changes here.
            flushSwiftDataIfNeeded()
            #endif
        }
        // Reset terminal on exit
        self.vtRenderer = nil
        self.renderer.vtRenderer = nil
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
        if !updateScheduled {
            Task { @MainActor [weak self] in
                try? await self?.update()
            }
            updateScheduled = true
        }
    }

    private var isUpdating = false
    private var needsAnotherUpdate = false
    private static let maxUpdateIterations = 8

    func update() async throws {
        guard !isUpdating else {
            needsAnotherUpdate = true
            return
        }
        isUpdating = true
        defer { isUpdating = false }

        var iterations = 0
        repeat {
            needsAnotherUpdate = false
            updateScheduled = false
            iterations += 1
            if iterations > Self.maxUpdateIterations {
                // Break silently: never write to stdout/stderr — that corrupts the TUI.
                break
            }

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
            if let vtRenderer = vtRenderer {
                // Soft caret must share the paint's Synchronized Update; a
                // separate CUP after present leaves the HW cursor on the last
                // damaged cell (often bottom-right) for one flush.
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
        } while needsAnotherUpdate
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
