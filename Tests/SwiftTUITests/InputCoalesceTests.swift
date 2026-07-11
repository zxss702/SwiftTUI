import XCTest
@testable import SwiftTUI

final class InputCoalesceTests: XCTestCase {
    func testCoalescingMouseMovesKeepsLatestMove() {
        let a = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .move))
        let b = VTEvent.mouse(MouseEvent(position: Position(x: 2, y: 2), type: .move))
        let c = VTEvent.mouse(MouseEvent(position: Position(x: 3, y: 3), type: .move))
        let key = VTEvent.key(KeyEvent(character: "a", keycode: 0, modifiers: [], type: .press))
        let click = VTEvent.mouse(MouseEvent(position: Position(x: 4, y: 4), type: .pressed(.left)))

        let result = VTEvent.coalescingMouseMoves([a, b, key, c, click])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], b)
        XCTAssertEqual(result[1], key)
        XCTAssertEqual(result[2], c)
        XCTAssertEqual(result[3], click)
    }
}
