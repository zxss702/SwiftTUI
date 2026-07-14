import Testing
@testable import SwiftTUI

@Suite(.serialized)
@MainActor
struct HostClockTests {

    @Test func scheduleAfterFiresOnce() async throws {
        let clock = HostClock()
        var hits = 0
        clock.schedule(after: 0.01) { hits += 1 }
        #expect(clock.pendingCount == 1)
        try await Task.sleep(for: .milliseconds(40))
        #expect(hits == 1)
        #expect(clock.pendingCount == 0)
    }

    @Test func cancelPreventsWork() async throws {
        let clock = HostClock()
        var hits = 0
        let id = clock.schedule(after: 0.05) { hits += 1 }
        clock.cancel(id)
        try await Task.sleep(for: .milliseconds(80))
        #expect(hits == 0)
    }

    @Test func scheduleNextTurnRuns() async throws {
        let clock = HostClock()
        var hits = 0
        clock.scheduleNextTurn { hits += 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(hits == 1)
    }

    @Test func repeatingCanBeCancelled() async throws {
        let clock = HostClock()
        var hits = 0
        let id = clock.scheduleRepeating(every: 0.01) { hits += 1 }
        try await Task.sleep(for: .milliseconds(45))
        clock.cancel(id)
        let frozen = hits
        #expect(frozen >= 2)
        try await Task.sleep(for: .milliseconds(40))
        #expect(hits == frozen)
    }
}
