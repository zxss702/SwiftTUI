import Foundation

/// Host-owned delayed work. Replaces `DispatchQueue.main.async` / `Timer`
/// in the View/Element layer with Swift concurrency on the MainActor.
@MainActor
final class HostClock {
    typealias WorkID = UUID

    private var pending: [WorkID: Task<Void, Never>] = [:]

    /// Fire once after `seconds`. Cancel with ``cancel(_:)``.
    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> WorkID {
        let id = WorkID()
        pending[id] = Task { @MainActor [weak self] in
            defer { self?.pending[id] = nil }
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            work()
        }
        return id
    }

    /// Repeat every `seconds` until cancelled.
    @discardableResult
    func scheduleRepeating(
        every seconds: TimeInterval,
        _ work: @escaping @MainActor () -> Void
    ) -> WorkID {
        let id = WorkID()
        pending[id] = Task { @MainActor [weak self] in
            defer { self?.pending[id] = nil }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                work()
            }
        }
        return id
    }

    /// Hop to the next MainActor turn (replaces `DispatchQueue.main.async`).
    @discardableResult
    func scheduleNextTurn(_ work: @escaping @MainActor () -> Void) -> WorkID {
        let id = WorkID()
        pending[id] = Task { @MainActor [weak self] in
            defer { self?.pending[id] = nil }
            await Task.yield()
            guard !Task.isCancelled else { return }
            work()
        }
        return id
    }

    func cancel(_ id: WorkID) {
        pending[id]?.cancel()
        pending.removeValue(forKey: id)
    }

    func cancelAll() {
        for task in pending.values {
            task.cancel()
        }
        pending.removeAll()
    }

    var pendingCount: Int { pending.count }
}
