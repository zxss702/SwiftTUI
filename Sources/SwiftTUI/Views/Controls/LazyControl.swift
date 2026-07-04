import Foundation

@MainActor
public protocol LazyControl {
    func updateVisibleRegion(offset: Extended, height: Extended)
}
