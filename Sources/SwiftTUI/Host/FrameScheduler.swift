import Foundation

/// Coalescing wake for non-input work (Observation, timers, residual dirty).
///
/// Input never goes through this stream — the host reads the terminal on its
/// own task and commits immediately so keystrokes cannot be buried behind a
/// growing `.frame` queue.
@MainActor
final class FrameScheduler {
    private let continuation: AsyncStream<Void>.Continuation

    /// Frame wakes. Consume from exactly one task for the lifetime of the host.
    let frames: AsyncStream<Void>

    /// True after `schedule()` until the host acknowledges a wake.
    private(set) var hasPendingWake = false

    /// Total `schedule()` calls (including coalesced). For tests.
    private(set) var scheduleCallCount = 0

    /// Wakes actually enqueued into the stream (coalesced count).
    private(set) var enqueuedWakeCount = 0

    init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.frames = stream
        self.continuation = continuation
    }

    /// Request a frame commit. Coalesces while a wake is already pending.
    func schedule() {
        scheduleCallCount &+= 1
        guard !hasPendingWake else { return }
        hasPendingWake = true
        enqueuedWakeCount &+= 1
        continuation.yield(())
    }

    /// Host consumed a frame wake (or is about to commit for other reasons).
    func acknowledgeWake() {
        hasPendingWake = false
    }

    /// Ends ``frames`` so the frame loop exits (app shutdown).
    func finish() {
        continuation.finish()
    }

    func testing_resetCounters() {
        scheduleCallCount = 0
        enqueuedWakeCount = 0
    }
}
