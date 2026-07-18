import Foundation

public struct Edges: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let top = Edges(rawValue: 1 << 0)
    public static let bottom  = Edges(rawValue: 1 << 1)
    public static let left = Edges(rawValue: 1 << 2)
    public static let right = Edges(rawValue: 1 << 3)

    /// 对齐 SwiftUI：`leading`/`trailing` 在 TUI（LTR）下等价于 `left`/`right`。
    public static var leading: Edges { .left }
    public static var trailing: Edges { .right }

    public static var all: Edges { [.top, .bottom, left, right] }
    public static var horizontal: Edges { [.left, .right] }
    public static var vertical: Edges { [.top, bottom] }
}
