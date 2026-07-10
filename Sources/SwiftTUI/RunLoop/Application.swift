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
        node = Node(view: ZStack(alignment: .center) { rootView }.view)
        node.build()

        control = node.control!

        window = Window()
        window.addControl(control)

        window.firstResponder = control.firstSelectableElement
        window.firstResponder?.becomeFirstResponder()
        
        renderer = Renderer(layer: window.layer)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self

        // 将 dismiss 注入到根节点环境，View 内通过 @Environment(\.dismiss) 获取
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
            
            #if os(Windows)
            // On Windows, WaitForSingleObject returns immediately for every event,
            // so the event stream never suspends to let scheduleUpdate()'s Task run.
            // For scroll events (which are high-frequency), call update() directly
            // to render each frame without being starved by the input loop.
            if isScroll {
                try? await update()
            } else {
                await Task.yield()
            }
            #endif
            
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
        
        let target = control.hitTest(position: pos)
        


        if target !== hoveredControl {
            hoveredControl?.isHovered = false
            target?.isHovered = true
            hoveredControl = target
        }
        
        if let target = target {
            target.handleMouseEvent(event)
            if case .pressed(.left) = event.type, target.selectable {
                window.firstResponder?.resignFirstResponder()
                window.firstResponder = target
                window.firstResponder?.becomeFirstResponder()
            }
        }
    }

    func invalidateNode(_ node: Node) {
        if !invalidatedNodes.contains(where: { $0 === node }) {
            invalidatedNodes.append(node)
            needsLayout = true
            scheduleUpdate()
        }
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

    func update() async throws {
        guard !isUpdating else {
            needsAnotherUpdate = true
            return
        }
        isUpdating = true
        
        repeat {
            needsAnotherUpdate = false
            updateScheduled = false


        if let size = pendingResizeSize {
            pendingResizeSize = nil
            window.layer.frame.size = size
            vtRenderer?.resize(to: size)
            control.layer.invalidate()
            needsLayout = true
        }

        for node in invalidatedNodes {
            node.update(using: node.view)
        }
        invalidatedNodes = []

        // Only do a full layout pass when data or size actually changed.
        // Pure scroll events do their own partial layout in the scroll handler.
        if needsLayout {
            control.layout(size: window.layer.frame.size)
            needsLayout = false
        }
        renderer.update()
        if let vtRenderer = vtRenderer {
            isPresenting = true
            await vtRenderer.present()
            isPresenting = false
            
            if let responder = window.firstResponder, let cursor = responder.cursorPosition {
                let absPos = responder.absoluteFrame.position
                let cursorX = absPos.column.intValue + cursor.column.intValue
                let cursorY = absPos.line.intValue + cursor.line.intValue
                await vtRenderer.terminal.write("\u{1B}[\(cursorY + 1);\(cursorX + 1)H\u{1B}[?25h")
            } else {
                await vtRenderer.terminal.write("\u{1B}[?25l")
            }
            }
        } while needsAnotherUpdate
        
        isUpdating = false
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
