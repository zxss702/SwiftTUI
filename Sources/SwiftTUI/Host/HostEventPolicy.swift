import Foundation

/// Policy for the serial host input pump.
///
/// DECSET 1003 delivers a mouse-move for every cell. Settling (Update→Paint→Present)
/// on each move blocks the input pump so keys/clicks sit behind a backlog — while
/// scroll/resize still eventually run, which matches "input frozen but scroll works".
enum HostEventPolicy {
    /// Events that must finish a settle before the pump reads the next event.
    static func requiresInlineSettle(_ event: VTEvent) -> Bool {
        switch event {
        case .key, .resize:
            return true
        case .mouse(let mouse):
            switch mouse.type {
            case .move:
                return false
            case .scroll, .pressed, .released:
                return true
            }
        }
    }
}
