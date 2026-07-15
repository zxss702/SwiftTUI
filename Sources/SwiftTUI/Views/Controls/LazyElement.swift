import Foundation

@MainActor
public protocol LazyElement {
    /// Updates which children are materialized for the visible scroll window.
    /// Returns `true` if children changed and the control needs layout.
    @discardableResult
    func updateVisibleRegion(offset: Extended, height: Extended) -> Bool
}

/// Lazy stacks that can resolve an `.id` to a content-Y offset without the
/// row already being on-screen (ScrollViewReader).
@MainActor
protocol LazyIdentityOffsetProviding: AnyObject {
    func contentLineOffset(forIdentity id: AnyHashable) -> Extended?
}
