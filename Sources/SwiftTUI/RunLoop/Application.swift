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

    public init<I: View>(rootView: I) {
        node = Node(view: VStack(content: rootView).view)
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
    }

    public func start() async throws {
        let vtRenderer = try await VTRenderer(mode: .raw)
        self.vtRenderer = vtRenderer
        self.renderer.vtRenderer = vtRenderer
        
        let terminal = vtRenderer.terminal
        await terminal.write("\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?7l")
        defer {
            let seq = "\u{1B}[?25h\u{1B}[?1049l\u{1B}[?7h"
            seq.withCString { _ = write(STDOUT_FILENO, $0, strlen($0)) }
            renderer.stop()
        }
        
        updateWindowSize(size: terminal.size)
        control.layout(size: window.layer.frame.size)
        renderer.draw()
        try await update()

        isRunning = true
        for try await event in terminal.input {
            if !isRunning { break }
            switch event {
            case .resize(let resizeEvent):
                handleWindowSizeChange(size: resizeEvent.size)
            case .key(let keyEvent):
                handleKeyInput(keyEvent)
            case .mouse(let mouseEvent):
                handleMouseInput(mouseEvent)
            }
            if !isRunning { break }
            
            // Fix Linux Task starvation: Yield the MainActor so any pending `invalidateNode` tasks 
            // queued by Observation/GRDB can run before we check `updateScheduled`.
            await Task.yield()
            if updateScheduled {
                try await update()
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
        } else if let ch = event.character {
            window.firstResponder?.handleEvent(ch)
        }
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
        }

        for node in invalidatedNodes {
            node.update(using: node.view)
        }
        invalidatedNodes = []

        control.layout(size: window.layer.frame.size)
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
