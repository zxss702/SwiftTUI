import Foundation

@MainActor public struct ForEach<Data, ID, Content>: View, PrimitiveView, ContiguousChildSource
where Data: RandomAccessCollection, ID: Hashable, Content: View {
    public var data: Data
    public var content: (Data.Element) -> Content
    private var id: KeyPath<Data.Element, ID>

    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content)
    where Data.Element: Identifiable, ID == Data.Element.ID {
        self.data = data
        self.content = content
        id = \.id
    }

    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.content = content
        self.id = id
    }

    static var size: Int? { nil }

    private static var rowsKey: String { "foreach.rows" }
    private static var flatCountKey: String { "foreach.flatCount" }
    private static var flatPrefixKey: String { "foreach.flatPrefix" }

    func buildNode(_ node: Node) {
        // 不预建 N 行；扁平 size / element 在首次查询时按需 ensure。
        node.storage[Self.rowsKey] = [Int: Node]()
        invalidateFlatCache(node)
    }

    func updateNode(_ node: Node) {
        let last = node.view as! Self
        node.view = self

        var rows = node.storage[Self.rowsKey] as? [Int: Node] ?? [:]

        let diff = data.difference(from: last.data, by: {
            $0[keyPath: id] == $1[keyPath: last.id]
        })

        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                if let child = rows.removeValue(forKey: offset) {
                    node.detachContiguousChild(child)
                }
                var shifted: [Int: Node] = [:]
                shifted.reserveCapacity(rows.count)
                for (key, child) in rows {
                    let newKey = key > offset ? key - 1 : key
                    node.setContiguousChildIndex(child, newKey)
                    shifted[newKey] = child
                }
                rows = shifted

            case .insert(let offset, _, _):
                var shifted: [Int: Node] = [:]
                shifted.reserveCapacity(rows.count)
                for (key, child) in rows {
                    let newKey = key >= offset ? key + 1 : key
                    node.setContiguousChildIndex(child, newKey)
                    shifted[newKey] = child
                }
                rows = shifted
            }
        }

        node.storage[Self.rowsKey] = rows
        // 行数/每行控件数可能变了；父级 LazyVStack/Grid 的 reloadContent 会按新 size 对齐。
        invalidateFlatCache(node)

        var lastByID: [ID: Data.Element] = [:]
        lastByID.reserveCapacity(last.data.count)
        for element in last.data {
            lastByID[element[keyPath: last.id]] = element
        }

        for (index, child) in rows {
            guard index < data.count else { continue }
            let element = data[data.index(data.startIndex, offsetBy: index)]
            let elementID = element[keyPath: id]
            if let previous = lastByID[elementID],
               StateEquality.areEqual(previous, element)
            {
                continue
            }
            child.update(using: content(element).view)
        }
    }

    // MARK: - ContiguousChildSource（扁平控件语义）

    func dataCount(node: Node) -> Int {
        data.count
    }

    func childNode(node: Node, at slot: Int) -> Node {
        ensureRow(node: node, at: slot)
    }

    func childCount(node: Node) -> Int {
        // 快路径：Content 静态 size 已知 → 无需 ensure 每一行。
        if let unit = Content.size {
            return unit == 0 ? 0 : data.count * unit
        }
        return rebuildFlatIndexIfNeeded(node: node)
    }

    func element(node: Node, at index: Int) -> Element {
        let flatCount = childCount(node: node)
        precondition(index >= 0 && index < flatCount, "ForEach flat index out of bounds")

        // 静态 size==1：扁平下标 == data 下标
        if Content.size == 1 {
            return ensureRow(node: node, at: index).element(at: 0)
        }
        if Content.size == 0 {
            fatalError("ForEach Content.size == 0 but element requested")
        }

        _ = rebuildFlatIndexIfNeeded(node: node)
        let prefix = node.storage[Self.flatPrefixKey] as! [Int]
        // prefix[i] = 第 i 行起始扁平下标；prefix[data.count] = 总长
        var lo = 0
        var hi = data.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if prefix[mid] <= index {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        let row = lo
        let local = index - prefix[row]
        let child = ensureRow(node: node, at: row)
        return child.element(at: local)
    }

    // MARK: - Private

    private func invalidateFlatCache(_ node: Node) {
        node.storage[Self.flatCountKey] = nil
        node.storage[Self.flatPrefixKey] = nil
    }

    @discardableResult
    private func rebuildFlatIndexIfNeeded(node: Node) -> Int {
        if let cached = node.storage[Self.flatCountKey] as? Int {
            return cached
        }
        var prefix: [Int] = []
        prefix.reserveCapacity(data.count + 1)
        prefix.append(0)
        var total = 0
        for i in 0 ..< data.count {
            let row = ensureRow(node: node, at: i)
            total += row.size
            prefix.append(total)
        }
        node.storage[Self.flatCountKey] = total
        node.storage[Self.flatPrefixKey] = prefix
        return total
    }

    private func ensureRow(node: Node, at index: Int) -> Node {
        precondition(index >= 0 && index < data.count, "ForEach data index out of bounds")
        var rows = node.storage[Self.rowsKey] as? [Int: Node] ?? [:]
        if let existing = rows[index] {
            return existing
        }
        let item = data[data.index(data.startIndex, offsetBy: index)]
        let child = Node(view: content(item).view)
        node.attachContiguousChild(child, at: index)
        if node.suppressUpdates {
            child.setSubtreeUpdateSuppressed(true)
        }
        rows[index] = child
        node.storage[Self.rowsKey] = rows
        return child
    }
}
