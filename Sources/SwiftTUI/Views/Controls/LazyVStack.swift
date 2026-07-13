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
        let control = node.control as! LazyVStackControl
        control.contentNode = node.children[0]
        control.totalChildrenSize = node.children[0].size
        // Trigger initial layout population
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.control = LazyVStackControl(
            alignment: alignment,
            spacing: spacing ?? 0,
            estimatedItemHeight: estimatedItemHeight
        )
        node.environment = { $0.stackOrientation = .vertical }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! LazyVStackControl
        control.alignment = alignment
        control.spacing = spacing ?? 0
        control.estimatedItemHeight = estimatedItemHeight
        // ForEach 增删会先走 insert/removeControl；这里再按 content 身份对齐缓存，
        // 避免 index 位移后仍挂着已删行的 Control。
        control.reloadContent(totalChildrenSize: node.children[0].size)
    }

    func insertControl(at index: Int, node: Node) {
        (node.control as! LazyVStackControl).handleInsert(at: index)
    }

    func removeControl(at index: Int, node: Node) {
        (node.control as! LazyVStackControl).handleRemove(at: index)
    }

    private class LazyVStackControl: Control, LazyControl {
        var alignment: HorizontalAlignment
        var spacing: Extended
        var estimatedItemHeight: Extended
        weak var contentNode: Node?
        var totalChildrenSize: Int = 0

        var lastOffset: Extended = 0
        var lastHeight: Extended = 100 // fallback initial
        private var lastStartIndex: Int?
        private var lastEndIndex: Int?

        private var loadedControls: [Int: Control] = [:]
        /// Measured heights for items that have been laid out; kept across unload so
        /// scroll-back reuses the last known size until the next measure.
        private var measuredHeights: [Int: Extended] = [:]

        func clearCache() {
            unloadAllLoadedControls()
            measuredHeights.removeAll()
            lastStartIndex = nil
            lastEndIndex = nil
        }

        /// Sync size / visible window. Drop indices past the end, and remount any
        /// slot whose Control no longer matches `contentNode` (ForEach middle delete).
        func reloadContent(totalChildrenSize: Int) {
            self.totalChildrenSize = totalChildrenSize
            var toRemove: [Int] = []
            for (i, _) in loadedControls where i >= totalChildrenSize {
                toRemove.append(i)
            }
            for i in toRemove {
                unloadControl(at: i)
            }
            for key in measuredHeights.keys where key >= totalChildrenSize {
                measuredHeights.removeValue(forKey: key)
            }
            if let contentNode {
                for (i, ctrl) in loadedControls {
                    let expected = contentNode.control(at: i)
                    if ctrl !== expected {
                        unloadControl(at: i)
                    }
                }
            }
            lastStartIndex = nil
            lastEndIndex = nil
            updateVisibleRegion(offset: lastOffset, height: lastHeight)
        }

        func handleInsert(at index: Int) {
            totalChildrenSize += 1
            for key in loadedControls.keys.filter({ $0 >= index }).sorted(by: >) {
                if let ctrl = loadedControls.removeValue(forKey: key) {
                    loadedControls[key + 1] = ctrl
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
            unloadControl(at: index)
            measuredHeights.removeValue(forKey: index)
            for key in loadedControls.keys.filter({ $0 > index }).sorted() {
                if let ctrl = loadedControls.removeValue(forKey: key) {
                    loadedControls[key - 1] = ctrl
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

        private func unloadAllLoadedControls() {
            for i in Array(loadedControls.keys) {
                unloadControl(at: i)
            }
        }

        private func unloadControl(at index: Int) {
            if let ctrl = loadedControls[index],
               let idx = children.firstIndex(where: { $0 === ctrl }) {
                removeSubview(at: idx)
            }
            loadedControls.removeValue(forKey: index)
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

        private func position(for index: Int) -> Extended {
            guard index > 0 else { return 0 }
            var line: Extended = 0
            for i in 0 ..< index {
                line += height(at: i)
                line += spacing
            }
            return line
        }

        private func totalContentHeight() -> Extended {
            guard totalChildrenSize > 0 else { return 0 }
            var total: Extended = 0
            for i in 0 ..< totalChildrenSize {
                total += height(at: i)
            }
            total += Extended(max(0, totalChildrenSize - 1)) * spacing
            return total
        }

        /// First index whose frame intersects [offset, offset + viewportHeight).
        private func firstVisibleIndex(offset: Extended) -> Int {
            guard totalChildrenSize > 0 else { return 0 }
            if offset <= 0 { return 0 }
            var line: Extended = 0
            for i in 0 ..< totalChildrenSize {
                let itemHeight = height(at: i)
                let next = line + itemHeight
                if next > offset { return i }
                line = next + spacing
            }
            return totalChildrenSize - 1
        }

        /// Last index whose frame intersects [offset, offset + viewportHeight).
        private func lastVisibleIndex(offset: Extended, viewportHeight: Extended) -> Int {
            guard totalChildrenSize > 0 else { return 0 }
            let bottom = offset + viewportHeight
            var line: Extended = 0
            var last = 0
            for i in 0 ..< totalChildrenSize {
                let itemHeight = height(at: i)
                if line < bottom {
                    last = i
                } else {
                    break
                }
                line += itemHeight + spacing
            }
            return last
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
            for (i, _) in loadedControls {
                if i < startIndex || i > endIndex {
                    toRemove.append(i)
                }
            }
            for i in toRemove {
                unloadControl(at: i)
            }

            // Only add items that are newly visible
            for i in startIndex...endIndex {
                if loadedControls[i] == nil {
                    let control = contentNode.control(at: i)
                    // Guard against an already-parented control (e.g. after a bad cache clear).
                    if control.parent == nil {
                        loadedControls[i] = control
                        addSubview(control, at: children.count)
                    } else if control.parent === self {
                        loadedControls[i] = control
                    } else {
                        // Detach from unexpected parent, then mount here.
                        if let oldParent = control.parent,
                           let idx = oldParent.children.firstIndex(where: { $0 === control }) {
                            oldParent.removeSubview(at: idx)
                        }
                        loadedControls[i] = control
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
            let indices = loadedControls.keys.sorted()
            for index in indices {
                guard let control = loadedControls[index] else { continue }

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

                control.layout(size: childSize)
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
