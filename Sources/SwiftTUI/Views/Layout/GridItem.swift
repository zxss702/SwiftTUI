import Foundation

/// A description of a single grid item, such as a column or a row.
public struct GridItem: Hashable, Sendable {
    public enum Size: Hashable, Sendable {
        /// A single item with the specified fixed size.
        case fixed(Extended)
        /// A single item with a flexible size within the specified bounds.
        case flexible(minimum: Extended = 10, maximum: Extended = .infinity)
        /// Multiple items in the space of a single flexible item.
        case adaptive(minimum: Extended, maximum: Extended = .infinity)
    }

    public var size: Size
    public var spacing: Extended?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: Extended? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}
