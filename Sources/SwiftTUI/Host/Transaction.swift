import Foundation

/// One frame's worth of pending work. Mutations enqueue here; the host commits
/// once per frame (Update → Layout → Paint → Present).
@MainActor
final class Transaction {
    /// Nodes whose view graph content must rebuild this frame.
    private var invalidated: [ObjectIdentifier: Node] = [:]

    /// Structural / size changes requiring a layout pass.
    private(set) var needsLayout = false

    /// Soft caret or popup chrome changed without a view rebuild.
    private(set) var needsPaint = false

    var isEmpty: Bool {
        invalidated.isEmpty && !needsLayout && !needsPaint
    }

    /// True when there is any committed work that must become visible.
    var hasWork: Bool { !isEmpty }

    var invalidatedNodes: [Node] {
        Array(invalidated.values)
    }

    func invalidate(_ node: Node, layout: Bool = false) {
        invalidated[ObjectIdentifier(node)] = node
        // Logical dirty always implies a pixel pass so State changes cannot
        // update the graph while skipping present.
        needsPaint = true
        if layout { needsLayout = true }
    }

    func requestLayout() {
        needsLayout = true
        needsPaint = true
    }

    func requestPaint() {
        needsPaint = true
    }

    /// Drain for the host's update loop. Layout/paint flags stay until the
    /// frame clears them after successful work.
    func takeInvalidatedNodes() -> [Node] {
        let nodes = Array(invalidated.values)
        invalidated.removeAll(keepingCapacity: true)
        return nodes
    }

    func clearLayout() {
        needsLayout = false
    }

    func clearPaint() {
        needsPaint = false
    }

    func reset() {
        invalidated.removeAll(keepingCapacity: true)
        needsLayout = false
        needsPaint = false
    }
}
