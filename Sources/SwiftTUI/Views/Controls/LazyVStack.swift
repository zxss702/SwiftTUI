import Foundation

@MainActor public struct LazyVStack<Content: View>: View, PrimitiveView, LayoutRootView {
    public let content: Content
    let alignment: HorizontalAlignment
    let spacing: Extended?
    let estimatedItemHeight: Extended

    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: Extended? = nil,
        estimatedItemHeight: Extended = 1,
        @ViewBuilder _ content: () -> Content
    ) {
        self.content = content()
        self.alignment = alignment
        self.spacing = spacing
        self.estimatedItemHeight = estimatedItemHeight
    }

    static var size: Int? { 1 }

    func loadData(node: Node) {
        let control = node.element as! LazyVStackElement
        control.contentNode = node.children[0]
        control.totalChildrenSize = node.children[0].size
        // Trigger initial layout population
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.element = LazyVStackElement(
            alignment: alignment,
            spacing: spacing ?? 0,
            estimatedItemHeight: estimatedItemHeight
        )
        node.environment = { $0.stackOrientation = .vertical }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! LazyVStackElement
        control.alignment = alignment
        control.spacing = spacing ?? 0
        control.estimatedItemHeight = estimatedItemHeight
        // ForEach 增删会先走 insert/removeElement；这里再按 content 身份对齐缓存，
        // 避免 index 位移后仍挂着已删行的 Element。
        if control.reloadContent(totalChildrenSize: node.children[0].size) {
            node.root.application?.requestLayout()
        }
    }

    func insertElement(at index: Int, node: Node) {
        (node.element as! LazyVStackElement).handleInsert(at: index)
    }

    func removeElement(at index: Int, node: Node) {
        (node.element as! LazyVStackElement).handleRemove(at: index)
    }

    private class LazyVStackElement: Element, LazyElement, LazyIdentityOffsetProviding {
        var alignment: HorizontalAlignment
        var spacing: Extended
        var estimatedItemHeight: Extended
        weak var contentNode: Node?
        var totalChildrenSize: Int = 0

        var lastOffset: Extended = 0
        var lastHeight: Extended = 100 // fallback initial
        private var lastStartIndex: Int?
        private var lastEndIndex: Int?

        private var loadedElements: [Int: Element] = [:]
        /// Measured heights for items that have been laid out; kept across unload so
        /// scroll-back reuses the last known size until the next measure.
        private var measuredHeights: [Int: Extended] = [:]

        /// `prefixSums[i]` = 第 i 项的顶边 y；`prefixSums[n]` = 总内容高度。
        /// 失效后按需重建，使 `position` / 可见区查找为 O(log n)。
        private var prefixSums: [Extended]?

        func contentLineOffset(forIdentity id: AnyHashable) -> Extended? {
            for (index, element) in loadedElements {
                if Self.containsIdentity(id, in: element) {
                    return position(for: index)
                }
            }
            guard let contentNode, totalChildrenSize > 0 else { return nil }
            // Probe unloaded slots from the END backwards. Building a row's element
            // forces that row's subtree (e.g. MarkdownView parse); the anchors used
            // in this app are always a trailing `Spacer().id(...)`, so reverse order
            // hits the anchor on the first step and builds only that one element
            // instead of parsing every message. Correct for any id (search order
            // only); `updateVisibleRegion` later remounts the same node.
            for i in stride(from: totalChildrenSize - 1, through: 0, by: -1) where loadedElements[i] == nil {
                let element = contentNode.element(at: i)
                if Self.containsIdentity(id, in: element) {
                    return position(for: i)
                }
            }
            return nil
        }

        private static func containsIdentity(_ id: AnyHashable, in control: Element) -> Bool {
            if let anchor = control as? IdentityAnchorElement, anchor.id == id {
                return true
            }
            for child in control.children {
                if containsIdentity(id, in: child) { return true }
            }
            return false
        }

        func clearCache() {
            unloadAllLoadedElements()
            measuredHeights.removeAll()
            invalidatePrefixSums()
            lastStartIndex = nil
            lastEndIndex = nil
        }

        /// Sync size / visible window. Drop indices past the end, and remount any
        /// slot whose Element no longer matches `contentNode` (ForEach middle delete).
        /// - Returns: `true` when a loaded slot was dropped (caller should relayout).
        @discardableResult
        func reloadContent(totalChildrenSize: Int) -> Bool {
            self.totalChildrenSize = totalChildrenSize
            invalidatePrefixSums()
            var remounted = false
            var toRemove: [Int] = []
            for (i, _) in loadedElements where i >= totalChildrenSize {
                toRemove.append(i)
            }
            for i in toRemove {
                unloadElement(at: i)
                remounted = true
            }
            for key in measuredHeights.keys where key >= totalChildrenSize {
                measuredHeights.removeValue(forKey: key)
            }
            if let contentNode {
                let swappingIdentity = loadedElements.contains { i, ctrl in
                    contentNode.element(at: i) !== ctrl
                }
                let window = root.window
                let previousSuppress = window?.suppressHoverResign ?? false
                if swappingIdentity {
                    window?.suppressHoverResign = true
                }
                defer { window?.suppressHoverResign = previousSuppress }
                for (i, ctrl) in loadedElements {
                    let expected = contentNode.element(at: i)
                    if ctrl !== expected {
                        unloadElement(at: i)
                        remounted = true
                    }
                }
            }
            lastStartIndex = nil
            lastEndIndex = nil
            updateVisibleRegion(offset: lastOffset, height: lastHeight)
            return remounted
        }

        func handleInsert(at index: Int) {
            totalChildrenSize += 1
            invalidatePrefixSums()
            for key in loadedElements.keys.filter({ $0 >= index }).sorted(by: >) {
                if let ctrl = loadedElements.removeValue(forKey: key) {
                    loadedElements[key + 1] = ctrl
                }
            }
            for key in measuredHeights.keys.filter({ $0 >= index }).sorted(by: >) {
                if let height = measuredHeights.removeValue(forKey: key) {
                    measuredHeights[key + 1] = height
                }
            }
            // Remount deferred to reloadContent — keeps one sync point after ForEach diff.
            lastStartIndex = nil
            lastEndIndex = nil
        }

        func handleRemove(at index: Int) {
            totalChildrenSize = max(0, totalChildrenSize - 1)
            invalidatePrefixSums()
            unloadElement(at: index)
            measuredHeights.removeValue(forKey: index)
            for key in loadedElements.keys.filter({ $0 > index }).sorted() {
                if let ctrl = loadedElements.removeValue(forKey: key) {
                    loadedElements[key - 1] = ctrl
                }
            }
            for key in measuredHeights.keys.filter({ $0 > index }).sorted() {
                if let height = measuredHeights.removeValue(forKey: key) {
                    measuredHeights[key - 1] = height
                }
            }
            // Do not remount here: removeNode still has the dying child in the tree.
            lastStartIndex = nil
            lastEndIndex = nil
        }

        private func unloadAllLoadedElements() {
            for i in Array(loadedElements.keys) {
                unloadElement(at: i)
            }
        }

        private func unloadElement(at index: Int) {
            if let ctrl = loadedElements[index],
               let idx = children.firstIndex(where: { $0 === ctrl }) {
                removeSubview(at: idx)
            }
            loadedElements.removeValue(forKey: index)
            // Keep measuredHeights[index] so total size / scroll mapping stay stable
            // until handleRemove / reloadContent shifts or drops the slot.
        }

        init(alignment: HorizontalAlignment, spacing: Extended, estimatedItemHeight: Extended) {
            self.alignment = alignment
            self.spacing = spacing
            self.estimatedItemHeight = estimatedItemHeight
        }

        private func height(at index: Int) -> Extended {
            measuredHeights[index] ?? estimatedItemHeight
        }

        private func invalidatePrefixSums() {
            prefixSums = nil
        }

        /// 重建前缀和：`prefix[i]` = item i 顶边，`prefix[n]` = 总高。
        private func ensurePrefixSums() {
            if let prefixSums, prefixSums.count == totalChildrenSize + 1 { return }
            var prefix: [Extended] = []
            prefix.reserveCapacity(totalChildrenSize + 1)
            prefix.append(0)
            guard totalChildrenSize > 0 else {
                prefixSums = prefix
                return
            }
            for i in 0 ..< totalChildrenSize {
                var next = prefix[i] + height(at: i)
                if i < totalChildrenSize - 1 {
                    next += spacing
                }
                prefix.append(next)
            }
            prefixSums = prefix
        }

        private func position(for index: Int) -> Extended {
            guard index > 0 else { return 0 }
            ensurePrefixSums()
            return prefixSums![min(index, totalChildrenSize)]
        }

        private func totalContentHeight() -> Extended {
            guard totalChildrenSize > 0 else { return 0 }
            ensurePrefixSums()
            return prefixSums![totalChildrenSize]
        }

        /// First index whose frame intersects [offset, offset + viewportHeight).
        private func firstVisibleIndex(offset: Extended) -> Int {
            guard totalChildrenSize > 0 else { return 0 }
            if offset <= 0 { return 0 }
            ensurePrefixSums()
            let prefix = prefixSums!
            // 最大的 i 使得 prefix[i] <= offset；若 item 完全在 offset 之上则前进。
            var lo = 0
            var hi = totalChildrenSize - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if prefix[mid] + height(at: mid) <= offset {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            return lo
        }

        /// Last index whose frame intersects [offset, offset + viewportHeight).
        private func lastVisibleIndex(offset: Extended, viewportHeight: Extended) -> Int {
            guard totalChildrenSize > 0 else { return 0 }
            let bottom = offset + viewportHeight
            ensurePrefixSums()
            let prefix = prefixSums!
            // 最大的 i 使得 prefix[i] < bottom
            var lo = 0
            var hi = totalChildrenSize - 1
            var answer = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if prefix[mid] < bottom {
                    answer = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            return answer
        }

        @discardableResult
        override func updateVisibleRegion(offset: Extended, height: Extended) -> Bool {
            lastOffset = offset
            lastHeight = height

            guard let contentNode = contentNode, totalChildrenSize > 0 else { return false }

            let buffer: Int = 5 // Load a few items before and after
            let safeHeight = height == .infinity ? 100 : height

            let rawStart = firstVisibleIndex(offset: offset)
            let rawEnd = lastVisibleIndex(offset: offset, viewportHeight: safeHeight)
            let startIndex = max(0, rawStart - buffer)
            let endIndex = min(totalChildrenSize - 1, rawEnd + buffer)

            if startIndex > endIndex { return false }
            if startIndex == lastStartIndex && endIndex == lastEndIndex { return false }
            lastStartIndex = startIndex
            lastEndIndex = endIndex

            // Incremental diff: only remove items that went off-screen
            var toRemove: [Int] = []
            for (i, _) in loadedElements {
                if i < startIndex || i > endIndex {
                    toRemove.append(i)
                }
            }
            for i in toRemove {
                unloadElement(at: i)
            }

            // Only add items that are newly visible
            for i in startIndex...endIndex {
                if loadedElements[i] == nil {
                    let control = contentNode.element(at: i)
                    // Guard against an already-parented control (e.g. after a bad cache clear).
                    if control.parent == nil {
                        loadedElements[i] = control
                        addSubview(control, at: children.count)
                    } else if control.parent === self {
                        loadedElements[i] = control
                    } else {
                        // Detach from unexpected parent, then mount here.
                        if let oldParent = control.parent,
                           let idx = oldParent.children.firstIndex(where: { $0 === control }) {
                            oldParent.removeSubview(at: idx)
                        }
                        loadedElements[i] = control
                        addSubview(control, at: children.count)
                    }
                }
            }

            layer.invalidate()
            return true
        }

        override func size(proposedSize: Size) -> Size {
            return Size(width: proposedSize.width, height: totalContentHeight())
        }

        override func layout(size: Size) {
            super.layout(size: size)

            // Same contract as VStack: propose the stack width, then layout at the
            // child's measured size (so wrap uses the proposal; frame size stays honest).
            var heightsChanged = false
            let indices = loadedElements.keys.sorted()
            var childSizes: [Int: Size] = [:]
            childSizes.reserveCapacity(indices.count)

            for index in indices {
                guard let control = loadedElements[index] else { continue }

                // `size()` 现在带换行缓存，宽度/内容不变即为 O(1) 命中。据此判断该行
                // 是否需要重新 layout：尺寸未变（滚动纯平移的常见情况）只更新位置，
                // 跳过整棵子树的递归 layout；尺寸变化（新挂载 / 宽度变化 / 内容更新）才重排。
                var childSize = control.size(proposedSize: Size(width: size.width, height: .infinity))
                // Unbounded-height children cannot contribute to scroll metrics; fall back
                // to the public estimate instead of inventing a clamped geometry.
                if childSize.height == .infinity {
                    childSize.height = estimatedItemHeight
                }
                if measuredHeights[index] != childSize.height {
                    heightsChanged = true
                }
                measuredHeights[index] = childSize.height
                childSizes[index] = childSize
            }

            // 高度都写入后再重建前缀和，避免循环内反复 O(n) ensurePrefixSums。
            if heightsChanged {
                invalidatePrefixSums()
            }

            for index in indices {
                guard let control = loadedElements[index],
                      let childSize = childSizes[index] else { continue }

                if control.layer.frame.size != childSize {
                    control.layout(size: childSize)
                }
                control.layer.frame.position.line = position(for: index)

                switch alignment {
                case .leading: control.layer.frame.position.column = 0
                case .center: control.layer.frame.position.column = (size.width - control.layer.frame.size.width) / 2
                case .trailing: control.layer.frame.position.column = size.width - control.layer.frame.size.width
                }
            }

            if heightsChanged {
                lastStartIndex = nil
                lastEndIndex = nil
            }
        }
    }
}
