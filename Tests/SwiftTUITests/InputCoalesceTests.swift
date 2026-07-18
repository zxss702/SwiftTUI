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

    func testCoalescingConsecutiveScrollsSumsDeltas() {
        let s1 = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .scroll(deltaX: 0, deltaY: 1)))
        let s2 = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 2), type: .scroll(deltaX: 0, deltaY: 2)))
        let s3 = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 3), type: .scroll(deltaX: 1, deltaY: -1)))
        let click = VTEvent.mouse(MouseEvent(position: Position(x: 2, y: 2), type: .pressed(.left)))

        let result = VTEvent.coalescingMouseMoves([s1, s2, s3, click])
        XCTAssertEqual(result.count, 2)
        guard case .mouse(let mouse) = result[0],
              case .scroll(let dx, let dy) = mouse.type else {
            return XCTFail("expected coalesced scroll")
        }
        XCTAssertEqual(dx, 1)
        XCTAssertEqual(dy, 2)
        XCTAssertEqual(mouse.position, Position(x: 1, y: 3))
        XCTAssertEqual(result[1], click)
    }

    func testCoalescingScrollsSeparatedByClickStaySeparate() {
        let s1 = VTEvent.mouse(MouseEvent(position: Position(x: 0, y: 0), type: .scroll(deltaX: 0, deltaY: 1)))
        let click = VTEvent.mouse(MouseEvent(position: Position(x: 1, y: 1), type: .pressed(.left)))
        let s2 = VTEvent.mouse(MouseEvent(position: Position(x: 0, y: 0), type: .scroll(deltaX: 0, deltaY: 1)))

        let result = VTEvent.coalescingMouseMoves([s1, click, s2])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1], click)
    }

    func testCoalescingInsertableKeysMergesPasteBurst() {
        let keys: [VTEvent] = "ab".map {
            .key(KeyEvent(character: $0, keycode: 0, modifiers: [], type: .press))
        }
        let result = VTEvent.coalescingTerminalEvents(keys)
        XCTAssertEqual(result.count, 1)
        guard case .textInput(let text) = result[0] else {
            return XCTFail("expected textInput")
        }
        XCTAssertEqual(text, "ab")
    }

    func testSingleKeyStaysKeyEvent() {
        let key = VTEvent.key(KeyEvent(character: "a", keycode: 0, modifiers: [], type: .press))
        let result = VTEvent.coalescingTerminalEvents([key])
        XCTAssertEqual(result.count, 1)
        guard case .key(let event) = result[0] else {
            return XCTFail("expected key")
        }
        XCTAssertEqual(event.character, "a")
    }

    func testBackspaceDoesNotMergeWithInsertableKeys() {
        let a = VTEvent.key(KeyEvent(character: "a", keycode: 0, modifiers: [], type: .press))
        let del = VTEvent.key(KeyEvent(character: "\u{7F}", keycode: 0, modifiers: [], type: .press))
        let b = VTEvent.key(KeyEvent(character: "b", keycode: 0, modifiers: [], type: .press))
        let result = VTEvent.coalescingTerminalEvents([a, del, b])
        XCTAssertEqual(result.count, 3)
        guard case .key = result[0], case .key = result[1], case .key = result[2] else {
            return XCTFail("expected three key events")
        }
    }
}
