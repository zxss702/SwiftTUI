import Foundation

/// 惰性连续子项容器（如 `ForEach`）：行 Node 按需创建，但对外暴露的
/// `size` / `element(at:)` 与旧版「扁平控件列表」语义一致（每行贡献 `row.size` 个槽）。
///
/// - `LazyVStack`：多数行 size==1，行为接近「一条 data 一槽」；`EmptyView` 行 size==0 不占槽。
/// - `LazyVGrid`：`Section` 等 size>1 的行会正确展开；`collectKinds` 通过 `childNode` 递归。
@MainActor protocol ContiguousChildSource: GenericView {
    /// 扁平控件个数（= 各行 `Node.size` 之和）。
    func childCount(node: Node) -> Int
    /// 按扁平下标取 Element。
    func element(node: Node, at index: Int) -> Element
    /// 确保第 `slot` 条 data 对应的行 Node 存在（供 LazyVGrid `collectKinds` 递归）。
    func childNode(node: Node, at slot: Int) -> Node
    /// data 条数（不是扁平控件数）。
    func dataCount(node: Node) -> Int
}
