import Testing
@testable import SwiftTUI

@Suite
struct TerminalReaderGateTests {
    @Test func claimInvalidatesPriorGeneration() {
        let first = StdinReaderGate.claim()
        #expect(StdinReaderGate.owns(first))

        let second = StdinReaderGate.claim()
        #expect(!StdinReaderGate.owns(first))
        #expect(StdinReaderGate.owns(second))
        #expect(first != second)
    }
}
