import Foundation

/// Policy for the serial host input pump.
///
/// The input task must never await Update→Paint→Present. Terminal present can
/// take 100ms–1s+; doing that inline on the pump freezes keys/clicks while
/// hover (move, no wake) and later scroll still appear to work.
///
/// DECSET 1003 floods mouse-move — those only wake the frame loop when commit
/// work is already pending. Keys/clicks/scroll/resize always wake so the frame
/// task can settle without blocking the next read.
enum HostEventPolicy {
    /// Whether this event should wake the frame loop after handling.
    static func shouldWakeFrameLoop(_ event: VTEvent) -> Bool {
        switch event {
        case .key, .textInput, .resize:
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
