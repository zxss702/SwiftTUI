import Foundation

@MainActor
public protocol LazyControl {
    /// Updates which children are materialized for the visible scroll window.
    /// Returns `true` if children changed and the control needs layout.
    @discardableResult
    func updateVisibleRegion(offset: Extended, height: Extended) -> Bool
}
