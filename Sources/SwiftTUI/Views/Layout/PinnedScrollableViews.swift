import Foundation

/// Views that can stick to the edges of a scrollable container while their section is visible.
/// Aligns SwiftUICore.`PinnedScrollableViews`.
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}
