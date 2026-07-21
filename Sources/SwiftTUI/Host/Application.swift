import Foundation
#if os(Windows)
import WinSDK
#endif

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

    /// Coalesced scroll-wheel deltas, applied once per frame in `update()`.
    /// Handling each wheel event inline on the input pump backed up a burst and
    /// made a direction reversal replay the queued forward scrolls first.
    private var pendingScrollDeltaX = 0
    private var pendingScrollDeltaY = 0
    private var pendingScrollPosition: Position?

    private var isRunning = false
    private var isUpdating = false
    /// `scheduleUpdate` during an open commit → one wake after the commit ends.
    private var needsReschedule = false
    private var lastSoftCursor: VTPosition?
    private var popupPresenter: PopupPresenter
    /// After terminal resize, clear the entire size-cache tree once.
    private var needsFullSizeCacheInvalidation = false

    /// After consuming a press that dismissed a light popup, ignore the matching
    /// release so it cannot synthesize another click.
    private var swallowNextMouseRelease = false

    /// Re-assert DECSET mouse modes once after the first click (some terminals
    /// only start 1003 motion after focus / first click).
    private var didReassertMouseModes = false

    /// TextField / TextEditor controls with staged Binding commits.
    private var pendingEditors: [ObjectIdentifier: Element] = [:]

    /// Last paint dirty rect (window coords); for tests / debug.
    private(set) var testing_lastPaintRect: Rect?

    /// Suppresses panel-refresh feedback while `refreshPresentedPanels` runs.
    private var isRefreshingPresentedPanels = false

    /// Last pointer position from the terminal. After a commit rebuilds
    /// elements, hover is re-resolved here so the fresh element instances
    /// take over enter/leave (a rebuilt row must still receive `false` later).
    private var lastMousePosition: Position?

    private static let maxUpdateIterations = 4

    /// DECSET off→on toggle: 1000 base clicks, 1002 drag, 1003 any-event
    /// (onHover), 1006 SGR coords. Some emulators mute 1003 until a hard
    /// re-enable, so always disable first.
    static let mouseModesSequence =
        "\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1003l\u{1B}[?1006l"
        + "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h"

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
        popupPresenter.hostWindow = window
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
        // Mouse: 1000 base; 1002 drag; 1003 any-event (onHover); 1006 SGR.
        // Toggle off→on after entering the alternate screen — some emulators
        // mute 1003 until a hard re-enable.
        let mouseOn = Self.mouseModesSequence
        await terminal.write(
            "\u{1B}[?1049h\u{1B}[2J\u{1B}[H\u{1B}[?25l\u{1B}[?7l" + mouseOn
        )
        defer {
            let seq =
                "\u{1B}[?25h\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006l\u{1B}[?1049l\u{1B}[?7h"
            seq.withCString { _ = write(STDOUT_FILENO, $0, numericCast(strlen($0))) }
            renderer.stop()
            self.vtRenderer = nil
            self.renderer.vtRenderer = nil
        }

        updateWindowSize(size: terminal.size)
        rootElement.layout(size: window.layer.frame.size)
        renderer.draw()
        try await flushPresent(force: true)
        await terminal.write(mouseOn)

        isRunning = true
        defer {
            isRunning = false
            clock.cancelAll()
            scheduler.finish()
            Self.drainPendingStdin()
        }

        let terminalInput = terminal.input
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Hover / Observation paints — never owns keys/clicks.
            group.addTask { [self] in
                await runFrameLoop()
            }
            // `nonisolated` pump: waiting on the terminal stream must not hold
            // MainActor across `present`/`update` (inherited task-group actor
            // context was serializing input behind frames → every-other feel).
            group.addTask { [self] in
                try await self.pumpTerminalInput(terminalInput)
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

    /// Read terminal events without holding ``MainActor``.
    ///
    /// DECSET 1003 floods `.move` events. Awaiting MainActor for *each* move
    /// (especially with debug logging) starved presses/keys in the pump — the
    /// terminal had already delivered them, but they sat behind hundreds of
    /// move hops. Moves are coalesced off the critical path; clicks/keys still
    /// run in order on MainActor.
    nonisolated private func pumpTerminalInput(_ terminalInput: VTEventStream) async throws {
        let moves = MoveCoalescingBridge()
        let flusher = Task { [moves] in
            while let move = await moves.next() {
                let ok = try? await Self.dispatchInputEvent(move, on: self)
                if ok == false { break }
            }
        }
        defer {
            flusher.cancel()
            Task { await moves.close() }
        }

        do {
            for try await event in terminalInput {
                if case .mouse(let mouse) = event, case .move = mouse.type {
                    await moves.post(event)
                    continue
                }
                // Deliver coalesced hover under the cursor before the click/key.
                if let move = await moves.takeLatest() {
                    let ok = try await Self.dispatchInputEvent(move, on: self)
                    if !ok { break }
                }
                let shouldContinue = try await Self.dispatchInputEvent(event, on: self)
                if !shouldContinue { break }
            }
            await moves.close()
        } catch is CancellationError {
            await moves.close()
        }
    }

    @MainActor
    private static func dispatchInputEvent(_ event: VTEvent, on app: Application) async throws -> Bool {
        guard app.isRunning else { return false }
        try await app.dispatchTerminalEvent(event)
        return app.isRunning
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

    /// Production input dispatch: handle, then wake the frame loop.
    /// Never await settle/present here — that blocked the pump for 100ms–1s+.
    func dispatchTerminalEvent(_ event: VTEvent) async throws {
        handleTerminalEvent(event)
        if HostEventPolicy.shouldWakeFrameLoop(event) || hasPendingCommitWork {
            scheduleUpdate()
        }
    }

    /// Drain dirty work + coalesced wakes with a hard cap (no infinite while-dirty).
    @discardableResult
    func settleHost(maxCommits: Int = 8) async throws -> Int {
        var commits = 0
        while commits < maxCommits {
            // Frame loop owns the open commit (often suspended in `present`).
            // Return immediately so the input pump can keep reading release/keys;
            // `scheduleUpdate` / commit deferral finishes the paint.
            if isUpdating {
                scheduleUpdate()
                return commits
            }

            if hasPendingCommitWork {
                let did = try await commitFrame()
                if did { commits += 1 }
                // Headless present does not suspend — yield so MainActor Tasks
                // (Observation) can land before we declare idle.
                await Task.yield()
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
            || pendingScrollDeltaX != 0
            || pendingScrollDeltaY != 0
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
        if !isRefreshingPresentedPanels {
            window.popupPresenter?.noteContentInvalidated()
        }
        // During an open commit, the update loop already drains `transaction`
        // via `needsAnother`. Scheduling here only set `needsReschedule` and
        // spawned extra frames (paint storms ~70ms full redraws).
        if !isUpdating {
            scheduleUpdate()
        }
    }

    func requestLayout() {
        transaction.requestLayout()
        if !isUpdating { scheduleUpdate() }
    }

    func requestPaint() {
        transaction.requestPaint()
        if !isUpdating { scheduleUpdate() }
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
        if !isUpdating { scheduleUpdate() }
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
        case .textInput(let string):
            handleTextInput(string)
        case .mouse(let mouseEvent):
            handleMouseInput(mouseEvent)
        }
    }

    /// Bulk insert from coalesced paste / typed burst — one shot to firstResponder.
    private func handleTextInput(_ string: String) {
        guard !string.isEmpty else { return }
        if let presenter = window.popupPresenter,
           presenter.isPresented,
           let host = presenter.top?.hostElement
        {
            let fr = window.firstResponder
            let focusInside =
                fr != nil && (fr === host || fr!.isDescendant(of: host))
            if focusInside {
                fr?.handleTextInput(string)
            } else {
                host.handleTextInput(string)
            }
            return
        }
        window.firstResponder?.handleTextInput(string)
    }

    func handleKeyInput(_ event: KeyEvent) {
        // Windows emits press+release; only act on press.
        guard event.type == .press else { return }

        if (event.character == "c" && event.modifiers.contains(.ctrl)) || event.character == "\u{03}" {
            // With an active selection Ctrl+C copies; without one the original
            // behavior (quit) is untouched.
            if let owner = window.selectionCoordinator.activeOwner,
               let text = owner.selectedText(), !text.isEmpty
            {
                Clipboard.copy(text, vtRenderer: vtRenderer)
                window.selectionCoordinator.clearActiveSelection()
                return
            }
            stop()
            return
        }

        #if DEBUG
        if event.character == "D" {
            dumpTree()
            return
        }
        #endif

        // While a presentation is open, keys go to the presented host (Escape /
        // menu) — not the underlying TextEditor — unless focus is already inside
        // the presentation (popover/modal with a text field).
        if let presenter = window.popupPresenter,
           presenter.isPresented,
           let host = presenter.top?.hostElement
        {
            let fr = window.firstResponder
            let focusInside =
                fr != nil && (fr === host || fr!.isDescendant(of: host))
            if focusInside {
                fr?.handleKeyEvent(event)
            } else {
                host.handleKeyEvent(event)
            }
            return
        }

        // Text focus only — Buttons / ScrollView never become firstResponder.
        window.firstResponder?.handleKeyEvent(event)
    }

    private func handleMouseInput(_ event: MouseEvent) {
        let pos = event.position
        lastMousePosition = pos
        let presenter = window.popupPresenter
        let lightPopup =
            presenter?.isPresented == true && presenter?.blocksUnderlyingHits == false
        let inPopupPanel = presenter?.panelFrame?.contains(pos) ?? false

        // Light menu: press outside panel (not on anchor) dismisses.
        if lightPopup, case .pressed(.left) = event.type {
            let onAnchor = presenter?.anchor.contains(pos) == true
            if !inPopupPanel, !onAnchor {
                window.cancelPointerGesture()
                swallowNextMouseRelease = true
                presenter?.dismiss()
                window.setHoveredElement(rootElement.hitTest(position: pos))
                return
            }
            if !inPopupPanel, onAnchor {
                window.cancelPointerGesture()
            }
        }

        if swallowNextMouseRelease, case .released = event.type {
            swallowNextMouseRelease = false
            window.cancelPointerGesture()
            window.setHoveredElement(hoverTarget(at: pos))
            return
        }

        switch event.type {
        case .pressed(let button):
            // A press anywhere cancels the active text selection (macOS-like);
            // dragging afterwards may immediately start a new one.
            window.selectionCoordinator.clearActiveSelection()
            // UIKit: hitTest → began. Same-target re-press keeps the session
            // (terminal sometimes repeats press without release); otherwise cancel.
            let target = rootElement.pointerGestureTarget(at: pos)
            if let session = window.pointerGesture,
               let existing = session.target,
               existing === target
            {
                // Same-target repeated press — keep the session.
            } else {
                window.cancelPointerGesture()
                if let target {
                    let began = target.pointerGesture(
                        PointerGestureEvent(phase: .began, position: pos, button: button)
                    )
                    // Only own a session when the target accepted `.began`
                    // (Buttons / editors). Scroll background etc. return false —
                    // leaving a dead session made later releases hit the wrong owner.
                    if began {
                        window.pointerGesture = PointerGestureSession(target: target, button: button, start: pos)
                        if target.retainsPointerCaptureAfterPress {
                            window.mouseCapture = target
                        }
                    }
                    if let leaf = rootElement.hitTest(position: pos),
                       let focus = leaf.focusTargetOnClick
                    {
                        window.setFirstResponder(focus)
                    }
                }
            }
            // Hard re-enable mouse modes on first click — terminals that mute
            // 1003 until interaction often start emitting moves after this.
            if !didReassertMouseModes, let terminal = vtRenderer?.terminalIfAvailable {
                didReassertMouseModes = true
                let mouseOn = Self.mouseModesSequence
                Task { @MainActor in
                    await terminal.write(mouseOn)
                }
            }
            window.setHoveredElement(hoverTarget(at: pos))

        case .move:
            if presenter?.isPresented == true {
                window.setHoveredElement(hoverTarget(at: pos))
            } else {
                window.setHoveredElement(rootElement.hitTest(position: pos))
            }
            if let session = window.pointerGesture, let target = session.target {
                _ = target.pointerGesture(
                    PointerGestureEvent(phase: .moved, position: pos, button: session.button)
                )
            } else if let capture = window.mouseCapture {
                _ = capture.consumeMouseEvent(event)
            }

        case .released(let button):
            if let session = window.pointerGesture, let target = session.target {
                _ = target.pointerGesture(
                    PointerGestureEvent(phase: .ended, position: pos, button: button)
                )
            }
            // Orphan releases (no session) are ignored — never synthesize a click.
            window.pointerGesture = nil
            window.mouseCapture = nil
            window.setHoveredElement(hoverTarget(at: pos))

        case .scroll(let deltaX, let deltaY):
            // Coalesce wheel deltas; the net delta is applied once per frame in
            // `update()` so a burst (or a direction reversal) does not replay
            // queued per-event layouts on the input pump.
            pendingScrollDeltaX += deltaX
            pendingScrollDeltaY += deltaY
            pendingScrollPosition = pos
            window.setHoveredElement(hoverTarget(at: pos))
        }
    }

    /// Dispatch the coalesced scroll delta (if any) as a single event.
    private func applyPendingScrollIfNeeded() {
        guard pendingScrollDeltaX != 0 || pendingScrollDeltaY != 0,
              let pos = pendingScrollPosition
        else { return }
        let merged = MouseEvent(
            position: pos,
            type: .scroll(deltaX: pendingScrollDeltaX, deltaY: pendingScrollDeltaY)
        )
        pendingScrollDeltaX = 0
        pendingScrollDeltaY = 0
        pendingScrollPosition = nil
        _ = rootElement.dispatchMouseEvent(merged)
        window.setHoveredElement(hoverTarget(at: pos))
    }

    /// Hover hit-test: while any presentation is open, only the presented host
    /// (and its descendants) may become `hoveredElement`. Outside a light popup
    /// panel → `nil` (underlying onHover stays frozen).
    ///
    /// Important: `hostElement` is attached on the next view update after
    /// `present()`. While the stack is non-empty but the host is not built yet,
    /// still isolate hover (`nil`) so underlying onHover does not see a leave.
    private func hoverTarget(at pos: Position) -> Element? {
        guard let presenter = window.popupPresenter, presenter.isPresented else {
            return rootElement.hitTest(position: pos)
        }
        guard let host = presenter.top?.hostElement else {
            return nil
        }
        // `Element.hitTest` expects parent-local coords; `pos` is window-absolute.
        let parentOrigin = host.parent?.absoluteFrame.position ?? .zero
        let inParent = Position(
            column: pos.column - parentOrigin.column,
            line: pos.line - parentOrigin.line
        )
        if presenter.blocksUnderlyingHits {
            return host.hitTest(position: inParent) ?? host
        }
        if let frame = presenter.panelFrame, frame.contains(pos) {
            return host.hitTest(position: inParent) ?? host
        }
        return nil
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
        // Apply coalesced scroll before layout so this frame reflects the net
        // wheel movement (reversals cancel queued forward deltas immediately).
        applyPendingScrollIfNeeded()

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

            // 2. Rebuild dirty view graph nodes (skip covered keep-alive pages).
            let nodes = transaction.takeInvalidatedNodes()
            var didUpdateNodes = false
            for node in nodes where node.isAttached(to: self) {
                if node.isUpdateSuppressed { continue }
                node.update(using: node.view)
                didUpdateNodes = true
            }
            if didUpdateNodes { hadViewUpdates = true }

            let presenter = window.popupPresenter
            let hadPanelRefresh = presenter?.needsPanelRefresh == true
            if hadPanelRefresh {
                isRefreshingPresentedPanels = true
                presenter?.refreshPresentedPanels()
                isRefreshingPresentedPanels = false
                hadViewUpdates = true
            }

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

            // 4. Paint from the accumulated dirty rect (no forced full-window expand).
            if window.layer.invalidated == nil, transaction.needsPaint {
                window.layer.invalidate()
            }
            if window.layer.invalidated != nil {
                testing_lastPaintRect = window.layer.invalidated
                renderer.update()
                transaction.clearPaint()
                didPaint = true
            }

            let needsAnother =
                !transaction.invalidatedNodes.isEmpty
                || transaction.needsLayout
                || !pendingEditors.isEmpty
                || presenter?.needsPanelRefresh == true
            if !needsAnother {
                break
            }
            if iterations == Self.maxUpdateIterations {
                needsReschedule = true
            }
        }

        // Hover is geometric, not identity-based. A rebuild/relayout can destroy
        // or move the element under the cursor (Window.hoveredElement is weak and
        // dangles), which used to swallow the leave (`onHover(false)`) for the
        // replacement row. Re-resolve against the *new* tree at the last pointer
        // position so fresh elements take over enter/leave.
        if hadViewUpdates || didLayout, let pos = lastMousePosition {
            window.setHoveredElement(hoverTarget(at: pos))
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
        if let fr = window.firstResponder,
           let absPos = fr.absoluteCursorPosition,
           absPos.line >= 0,
           absPos.column >= 0,
           absPos.line < window.layer.frame.size.height,
           absPos.column < window.layer.frame.size.width,
           softCursorAllowed(for: fr)
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

    /// Sheet / alert grey out the underlay — never park the HW caret on dimmed content.
    private func softCursorAllowed(for firstResponder: Element) -> Bool {
        guard let presenter = window.popupPresenter,
              presenter.isPresented,
              presenter.blocksUnderlyingHits,
              let host = presenter.top?.hostElement
        else { return true }
        return firstResponder === host || firstResponder.isDescendant(of: host)
    }

    func updateWindowSize(size: Size) {
        window.layer.frame.size = size
    }

    private func stop() {
        isRunning = false
        // Kick any parked stdin/console reader so the next Application.start()
        // is not racing the previous session for input events.
        _ = StdinReaderGate.claim()
        clock.cancelAll()
        scheduler.finish()
        // Discard tty bytes already queued (e.g. the click's release after
        // dismiss). Otherwise the *next* Application sees orphan releases.
        Self.drainPendingStdin()
    }

    /// Non-blocking drain of stdin so a sequential `Application.start()` does
    /// not inherit stale press/release bytes from the previous session.
    nonisolated private static func drainPendingStdin() {
        #if os(Windows)
        let handle = GetStdHandle(STD_INPUT_HANDLE)
        guard handle != INVALID_HANDLE_VALUE else { return }
        _ = FlushConsoleInputBuffer(handle)
        #else
        let fd = STDIN_FILENO
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var buf = [UInt8](repeating: 0, count: 256)
        while read(fd, &buf, buf.count) > 0 {}
        _ = fcntl(fd, F_SETFL, flags)
        #endif
    }
}

// MARK: - Move coalescing (input pump)

/// Newest-wins slot so the input reader never awaits MainActor per DECSET 1003 move.
private actor MoveCoalescingBridge {
    private var latest: VTEvent?
    private var waiter: CheckedContinuation<VTEvent?, Never>?
    private var closed = false

    func post(_ event: VTEvent) {
        guard !closed else { return }
        latest = event
        if let waiter {
            self.waiter = nil
            let value = latest
            latest = nil
            waiter.resume(returning: value)
        }
    }

    /// Steal the pending move for the click/key path (ordering before the click).
    func takeLatest() -> VTEvent? {
        let event = latest
        latest = nil
        return event
    }

    /// Suspend until a move is posted, or nil when closed.
    func next() async -> VTEvent? {
        if closed { return nil }
        if let event = latest {
            latest = nil
            return event
        }
        return await withCheckedContinuation { continuation in
            if closed {
                continuation.resume(returning: nil)
                return
            }
            if let event = latest {
                latest = nil
                continuation.resume(returning: event)
                return
            }
            waiter = continuation
        }
    }

    func close() {
        closed = true
        latest = nil
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: nil)
        }
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

    /// Production dispatch + frame settle (tests have no frame-loop task).
    func testing_turn(input: VTEvent? = nil) async throws {
        if let input {
            try await dispatchTerminalEvent(input)
        }
        try await settleHost()
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
        let commits = try await settleHost(maxCommits: maxCommits)
        // Headless tests have no frame loop to consume the buffered wake;
        // clear the flag so post-drain `schedule()` enqueues observably.
        if !hasPendingCommitWork {
            scheduler.acknowledgeWake()
        }
        return commits
    }

    var testing_scheduler: FrameScheduler { scheduler }

    var testing_rootElement: Element { rootElement }

    var testing_isUpdating: Bool { isUpdating }

    /// Layout + paint through the *real* VT double-buffer + damage pipeline
    /// (no terminal IO). Unlike `testing_prepare`, which draws a fresh
    /// `ScreenBuffer` from scratch each inspection, this keeps a persistent
    /// back buffer with partial dirty-rect redraws — required to reproduce
    /// stale-cell bugs (e.g. a popover close leaving torn glyphs behind).
    func testing_prepareVT(
        size: Size = Size(width: 80, height: 24),
        terminal: (any VTTerminal)? = nil
    ) async throws {
        let vt = VTRenderer(testing: size, terminal: terminal)
        vtRenderer = vt
        renderer.vtRenderer = vt
        updateWindowSize(size: size)
        transaction.requestLayout()
        transaction.requestPaint()
        window.layer.invalidate()
        _ = try await commitFrame()
        try await testing_drainUntilIdle()
    }

    /// Character currently held in the VT back buffer (the persistent screen
    /// state) at a 0-based window position. `nil` when out of bounds or when
    /// no VT renderer is installed. Wide-char continuation cells read `\u{0000}`.
    func testing_vtCharacter(at position: Position) -> Character? {
        guard let vtRenderer else { return nil }
        let size = vtRenderer.back.size
        let row = position.line.intValue + 1
        let column = position.column.intValue + 1
        guard row >= 1, column >= 1, row <= size.heightInt, column <= size.widthInt else {
            return nil
        }
        return vtRenderer.back[VTPosition(row: row, column: column)].character
    }
}
