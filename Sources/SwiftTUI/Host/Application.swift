import Foundation

/// Application host: input commits on the reader task; frame wakes are coalesced.
@MainActor
public final class Application {
    private let node: Node
    let window: Window
    private let rootElement: Element
    private let renderer: Renderer
    private var vtRenderer: VTRenderer?

    private let transaction = Transaction()
    private let scheduler = FrameScheduler()
    let clock = HostClock()

    private var pendingResizeSize: Size?
    private var isRunning = false
    private var isUpdating = false
    /// `scheduleUpdate` during an open commit → one wake after the commit ends.
    private var needsReschedule = false
    private var lastSoftCursor: VTPosition?
    private var popupPresenter: PopupPresenter
    /// After terminal resize, clear the entire size-cache tree once.
    private var needsFullSizeCacheInvalidation = false

    /// TextField / TextEditor controls with staged Binding commits.
    private var pendingEditors: [ObjectIdentifier: Element] = [:]

    private static let maxUpdateIterations = 4

    public init<I: View>(rootView: I) {
        let popupPresenter = PopupPresenter()
        self.popupPresenter = popupPresenter

        node = Node(
            view: ZStack(alignment: .center) {
                rootView
                PopupOverlayHost()
            }.view
        )
        node.environment = { env in
            env[PopupPresenter.self] = popupPresenter
        }
        node.build()

        rootElement = node.element!
        window = Window()
        window.popupPresenter = popupPresenter
        window.addElement(rootElement)
        window.setFirstResponder(rootElement.firstSelectableElement)

        renderer = Renderer(layer: window.layer)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self

        let oldEnv = self.node.environment
        self.node.environment = { [weak self] env in
            oldEnv?(&env)
            env.dismiss = DismissAction {
                self?.stop()
            }
        }

        // `node.build()` ran before `application` was attached, so Observation
        // invalidates from build-time side effects (navigationTitle/toolbar) were
        // dropped. Mark the root dirty so the first commit refreshes chrome.
        invalidateNode(node)
    }

    public func start() async throws {
        let vtRenderer = try await VTRenderer(mode: .raw)
        self.vtRenderer = vtRenderer
        self.renderer.vtRenderer = vtRenderer

        let terminal = vtRenderer.terminal
        await terminal.write("\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?7l\u{1B}[?1003h\u{1B}[?1006h")
        defer {
            let seq = "\u{1B}[?25h\u{1B}[?1003l\u{1B}[?1006l\u{1B}[?1049l\u{1B}[?7h"
            seq.withCString { _ = write(STDOUT_FILENO, $0, numericCast(strlen($0))) }
            renderer.stop()
            self.vtRenderer = nil
            self.renderer.vtRenderer = nil
        }

        updateWindowSize(size: terminal.size)
        rootElement.layout(size: window.layer.frame.size)
        renderer.draw()
        try await flushPresent(force: true)

        isRunning = true
        defer {
            isRunning = false
            clock.cancelAll()
            scheduler.finish()
        }

        let terminalInput = terminal.input
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Hover / Observation paints — never owns keys/clicks.
            group.addTask { [self] in
                await runFrameLoop()
            }
            group.addTask { [self] in
                try await runInputLoop(terminalInput)
            }

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

    private func runInputLoop(_ terminalInput: VTEventStream) async throws {
        do {
            for try await event in terminalInput {
                guard isRunning else { break }
                try await dispatchTerminalEvent(event)
            }
        } catch is CancellationError {
        }
    }

    private func runFrameLoop() async {
        for await _ in scheduler.frames {
            guard isRunning else { break }
            scheduler.acknowledgeWake()
            if isUpdating {
                scheduler.schedule()
                continue
            }
            do {
                _ = try await settleHost()
            } catch is CancellationError {
            } catch {
            }
        }
    }

    /// Production input dispatch: handle, then settle only when the event must
    /// be visible before the next read (not on mouse-move floods).
    func dispatchTerminalEvent(_ event: VTEvent) async throws {
        // #region agent log
        let settle = HostEventPolicy.requiresInlineSettle(event)
        DebugSessionLog.write(
            hypothesisId: "C",
            location: "Application.dispatchTerminalEvent:entry",
            message: "dispatch",
            data: [
                "event": String(describing: event),
                "inlineSettle": settle,
                "isUpdating": isUpdating,
                "hasPending": hasPendingCommitWork,
                "fr": DebugSessionLog.typeName(window.firstResponder),
                "capture": DebugSessionLog.typeName(window.mouseCapture),
            ]
        )
        // #endregion
        handleTerminalEvent(event)
        if settle {
            // #region agent log
            let t0 = Date().timeIntervalSince1970
            // #endregion
            try await settleHost()
            // #region agent log
            DebugSessionLog.write(
                hypothesisId: "C",
                location: "Application.dispatchTerminalEvent:afterSettle",
                message: "settle done",
                data: [
                    "ms": Int((Date().timeIntervalSince1970 - t0) * 1000),
                    "isUpdating": isUpdating,
                    "hasPending": hasPendingCommitWork,
                    "fr": DebugSessionLog.typeName(window.firstResponder),
                ]
            )
            // #endregion
        } else if hasPendingCommitWork {
            scheduleUpdate()
        }
    }

    /// Drain dirty work + coalesced wakes with a hard cap (no infinite while-dirty).
    @discardableResult
    func settleHost(maxCommits: Int = 8) async throws -> Int {
        var commits = 0
        var yieldsWhileBusy = 0
        while commits < maxCommits {
            // Another task holds the commit lock (usually frame settle during
            // `await present`). Yield — do not burn the commit budget on no-ops.
            if isUpdating {
                yieldsWhileBusy += 1
                if yieldsWhileBusy > 64 { break }
                await Task.yield()
                continue
            }
            yieldsWhileBusy = 0

            if hasPendingCommitWork {
                let did = try await commitFrame()
                if did { commits += 1 }
                // Headless present does not suspend — yield so MainActor Tasks
                // (Observation) can land before we declare idle.
                await Task.yield()
                continue
            }
            if scheduler.hasPendingWake {
                scheduler.acknowledgeWake()
                continue
            }
            break
        }
        return commits
    }

    var hasPendingCommitWork: Bool {
        !transaction.isEmpty
            || window.layer.invalidated != nil
            || !pendingEditors.isEmpty
            || pendingResizeSize != nil
    }

    var swiftDataContext: ModelContext?

    @MainActor
    private func flushSwiftDataIfNeeded() {
        if let context = swiftDataContext, context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    public func modelContainer(_ container: ModelContainer) -> Self {
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

    // MARK: - Invalidation API (view graph → transaction)

    func invalidateNode(_ node: Node, layout: Bool = false) {
        guard node.isAttached(to: self) else { return }
        transaction.invalidate(node, layout: layout)
        window.popupPresenter?.noteContentInvalidated()
        scheduleUpdate()
    }

    func requestLayout() {
        transaction.requestLayout()
        scheduleUpdate()
    }

    func requestPaint() {
        transaction.requestPaint()
        scheduleUpdate()
    }

    func scheduleUpdate() {
        // Never enqueue wakes while a commit is open — that grew an unbounded
        // frame backlog and starved the old shared HostEvent queue.
        if isUpdating {
            needsReschedule = true
            return
        }
        scheduler.schedule()
    }

    /// Stage an editor's Binding flush for the next commit.
    func noteEditorNeedsCommit(_ control: Element) {
        pendingEditors[ObjectIdentifier(control)] = control
        transaction.requestPaint()
        scheduleUpdate()
    }

    private func flushPendingEditorCommits() {
        let editors = Array(pendingEditors.values)
        pendingEditors.removeAll(keepingCapacity: true)
        for editor in editors {
            editor.commitBindingIfNeeded()
        }
    }

    // MARK: - Input

    func handleTerminalEvent(_ event: VTEvent) {
        switch event {
        case .resize(let resizeEvent):
            pendingResizeSize = resizeEvent.size
            transaction.requestLayout()
            transaction.requestPaint()
        case .key(let keyEvent):
            handleKeyInput(keyEvent)
        case .mouse(let mouseEvent):
            handleMouseInput(mouseEvent)
        }
    }

    func handleKeyInput(_ event: KeyEvent) {
        // Windows emits press+release; only act on press.
        guard event.type == .press else { return }

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

        // #region agent log
        DebugSessionLog.write(
            hypothesisId: "A",
            location: "Application.handleKeyInput",
            message: "key",
            data: [
                "char": event.character.map(String.init) ?? "",
                "fr": DebugSessionLog.typeName(window.firstResponder),
                "frCanFocus": window.firstResponder?.canReceiveFocus ?? false,
            ]
        )
        // #endregion

        // Keys go only to firstResponder — never broadcast down the tree.
        window.firstResponder?.handleKeyEvent(event)
    }

    private func handleMouseInput(_ event: MouseEvent) {
        let pos = event.position

        if let capture = window.mouseCapture {
            switch event.type {
            case .move, .released:
                // #region agent log
                if case .released = event.type {
                    DebugSessionLog.write(
                        hypothesisId: "B",
                        location: "Application.handleMouseInput:captureRelease",
                        message: "release to capture",
                        data: [
                            "capture": DebugSessionLog.typeName(capture),
                            "pos": "\(pos.column),\(pos.line)",
                        ]
                    )
                }
                // #endregion
                capture.handleMouseEvent(event)
                if case .released = event.type {
                    window.mouseCapture = nil
                }
                window.setHoveredElement(rootElement.hitTest(position: pos))
                return
            default:
                break
            }
        }

        let target = rootElement.hitTest(position: pos)

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

        // #region agent log
        switch event.type {
        case .pressed, .released:
            DebugSessionLog.write(
                hypothesisId: "D",
                location: "Application.handleMouseInput:click",
                message: "mouse click path",
                data: [
                    "type": String(describing: event.type),
                    "pos": "\(pos.column),\(pos.line)",
                    "target": DebugSessionLog.typeName(target),
                    "targetCanFocus": target?.canReceiveFocus ?? false,
                    "frBefore": DebugSessionLog.typeName(window.firstResponder),
                    "popupPresented": window.popupPresenter?.isPresented ?? false,
                    "dismissOutside": shouldDismissPopup,
                ]
            )
        default:
            break
        }
        // #endregion

        window.setHoveredElement(target)

        if let target {
            target.handleMouseEvent(event)
            if case .pressed(.left) = event.type, target.canReceiveFocus {
                window.setFirstResponder(target)
            }
        }

        if shouldDismissPopup {
            window.popupPresenter?.dismiss()
        }
    }

    // MARK: - Frame pipeline

    /// Returns `true` when a commit actually ran.
    @discardableResult
    func commitFrame() async throws -> Bool {
        guard !isUpdating else {
            needsReschedule = true
            return false
        }
        isUpdating = true
        needsReschedule = false
        defer {
            isUpdating = false
            if needsReschedule || hasPendingCommitWork {
                needsReschedule = false
                scheduler.schedule()
            }
        }
        try await update()
        return true
    }

    func update() async throws {
        if let size = pendingResizeSize {
            pendingResizeSize = nil
            window.layer.frame.size = size
            vtRenderer?.resize(to: size)
            rootElement.layer.invalidate()
            needsFullSizeCacheInvalidation = true
            transaction.requestLayout()
            transaction.requestPaint()
        }

        var iterations = 0
        var hadViewUpdates = false
        var didLayout = false
        var didPaint = false

        while iterations < Self.maxUpdateIterations {
            iterations += 1

            // 1. Flush staged editor → Binding writes (may invalidate nodes).
            flushPendingEditorCommits()

            // 2. Rebuild dirty view graph nodes.
            let nodes = transaction.takeInvalidatedNodes()
            let hadNodes = !nodes.isEmpty
            if hadNodes { hadViewUpdates = true }
            for node in nodes where node.isAttached(to: self) {
                node.update(using: node.view)
            }

            let presenter = window.popupPresenter
            let hadPanelRefresh = presenter?.needsPanelRefresh == true
            presenter?.refreshPresentedPanels()
            if hadPanelRefresh { hadViewUpdates = true }

            // 3. Layout only when requested.
            var layoutPasses = 0
            while transaction.needsLayout, layoutPasses < 4 {
                transaction.clearLayout()
                if needsFullSizeCacheInvalidation {
                    rootElement.invalidateSizeCache()
                    needsFullSizeCacheInvalidation = false
                }
                rootElement.layout(size: window.layer.frame.size)
                layoutPasses += 1
                didLayout = true
                window.layer.invalidate()
            }

            // 4. Paint once per iteration. View work without a dirty rect still
            //    forces a full-window invalidate so State changes are visible.
            if window.layer.invalidated == nil, transaction.needsPaint || hadNodes {
                window.layer.invalidate()
            }
            if window.layer.invalidated != nil {
                renderer.update()
                transaction.clearPaint()
                didPaint = true
            }

            let needsAnother =
                !transaction.invalidatedNodes.isEmpty
                || transaction.needsLayout
                || !pendingEditors.isEmpty
                || presenter?.needsPanelRefresh == true
            if !hadNodes, !hadPanelRefresh, !needsAnother {
                break
            }
            if iterations == Self.maxUpdateIterations, needsAnother {
                needsReschedule = true
            }
        }

        flushSwiftDataIfNeeded()

        // Present whenever this frame did real work — never leave the graph
        // updated while the terminal still shows the previous frame.
        let mustPresent = didPaint || didLayout || hadViewUpdates
        try await flushPresent(force: mustPresent)
    }

    private func flushPresent(force: Bool) async throws {
        guard let vtRenderer else { return }

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

        let cursorChanged = softCursor != lastSoftCursor
        lastSoftCursor = softCursor

        guard force || cursorChanged else { return }
        await vtRenderer.present(cursor: softCursor)
    }

    func updateWindowSize(size: Size) {
        window.layer.frame.size = size
    }

    private func stop() {
        isRunning = false
        clock.cancelAll()
        scheduler.finish()
    }
}

// MARK: - Headless test harness

extension Application {
    /// Layout + paint without a real terminal (present is a no-op).
    func testing_prepare(size: Size = Size(width: 80, height: 24)) async throws {
        updateWindowSize(size: size)
        transaction.requestLayout()
        transaction.requestPaint()
        window.layer.invalidate()
        _ = try await commitFrame()
        try await testing_drainUntilIdle()
    }

    /// Same path as the live input pump (``dispatchTerminalEvent``).
    func testing_turn(input: VTEvent? = nil) async throws {
        if let input {
            try await dispatchTerminalEvent(input)
        } else {
            try await settleHost()
        }
    }

    /// Strict one-commit turn (no residual drain) — used to catch one-behind.
    func testing_turnSingleCommit(input: VTEvent? = nil) async throws {
        if let input {
            handleTerminalEvent(input)
        }
        if hasPendingCommitWork {
            _ = try await commitFrame()
        }
    }

    /// Old buggy shape: settle on every event including mouse-move (for contrast tests).
    func testing_turnAlwaysSettle(input: VTEvent) async throws -> Int {
        handleTerminalEvent(input)
        return try await settleHost()
    }

    @discardableResult
    func testing_drainUntilIdle(maxCommits: Int = 64) async throws -> Int {
        try await settleHost(maxCommits: maxCommits)
    }

    var testing_scheduler: FrameScheduler { scheduler }

    var testing_rootElement: Element { rootElement }

    var testing_isUpdating: Bool { isUpdating }
}
