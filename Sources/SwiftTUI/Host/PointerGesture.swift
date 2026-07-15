import Foundation

/// One in-flight pointer gesture (UIKit `touchesBegan` → `Moved` → `Ended`).
///
/// `Application` hit-tests on press, stores the owner here, and routes move/end
/// to that same target — never invents a press from an orphan release.
@MainActor
struct PointerGestureSession {
    weak var target: Element?
    let button: MouseButton
    let start: Position
}

/// Phase delivered to the gesture owner after hit-testing.
@MainActor
struct PointerGestureEvent {
    enum Phase: Equatable {
        case began
        case moved
        case ended
        case cancelled
    }

    let phase: Phase
    let position: Position
    let button: MouseButton
}
