import Foundation

// MARK: - NavigationPath

/// 和 SwiftUI.NavigationPath 保持一致的路由栈类型。
/// 可以持有任意 Hashable 值，是导航状态的唯一来源。
public struct NavigationPath: Equatable {
    var elements: [AnyHashable] = []

    public init() {}

    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// 路由栈是否为空（即当前显示根视图）
    public var isEmpty: Bool { elements.isEmpty }

    /// 路由栈中的元素数量
    public var count: Int { elements.count }

    /// 向路由栈中 push 一个新值
    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    /// 从路由栈中 pop 最后一个值
    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }

    public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool {
        lhs.elements == rhs.elements
    }
}
