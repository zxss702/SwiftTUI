import Foundation

@MainActor public struct LazyVStack<Content: View>: View, PrimitiveView, LayoutRootView {
    public let content: Content
    let alignment: HorizontalAlignment
    let spacing: Extended?

    public init(alignment: HorizontalAlignment = .leading, spacing: Extended? = nil, @ViewBuilder _ content: () -> Content) {
        self.content = content()
        self.alignment = alignment
        self.spacing = spacing
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
        node.control = LazyVStackControl(alignment: alignment, spacing: spacing ?? 0)
        node.environment = { $0.stackOrientation = .vertical }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! LazyVStackControl
        control.alignment = alignment
        control.spacing = spacing ?? 0
        // Reuse already-mounted controls; only drop out-of-range entries and refresh
        // the visible window. Clearing the cache without removeSubview used to
        // duplicate children on every parent @State refresh.
        control.reloadContent(totalChildrenSize: node.children[0].size)
    }

    func insertControl(at index: Int, node: Node) {
        // Handled dynamically by LazyVStackControl
    }

    func removeControl(at index: Int, node: Node) {
        // Handled dynamically by LazyVStackControl
    }

        private class LazyVStackControl: Control, LazyControl {
        var alignment: HorizontalAlignment
        var spacing: Extended
        weak var contentNode: Node?
        var totalChildrenSize: Int = 0

        var lastOffset: Extended = 0
        var lastHeight: Extended = 100 // fallback initial
        private var lastStartIndex: Int?
        private var lastEndIndex: Int?

        private var loadedControls: [Int: Control] = [:]

        func clearCache() {
            unloadAllLoadedControls()
            lastStartIndex = nil
            lastEndIndex = nil
        }

        /// Update data source size and refresh the visible window without
        /// duplicating already-mounted subviews.
        func reloadContent(totalChildrenSize: Int) {
            self.totalChildrenSize = totalChildrenSize
            var toRemove: [Int] = []
            for (i, _) in loadedControls where i >= totalChildrenSize {
                toRemove.append(i)
            }
            for i in toRemove {
                unloadControl(at: i)
            }
            lastStartIndex = nil
            lastEndIndex = nil
            updateVisibleRegion(offset: lastOffset, height: lastHeight)
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
        }

        init(alignment: HorizontalAlignment, spacing: Extended) {
            self.alignment = alignment
            self.spacing = spacing
        }

        @discardableResult
        override func updateVisibleRegion(offset: Extended, height: Extended) -> Bool {
            lastOffset = offset
            lastHeight = height
            
            guard let contentNode = contentNode, totalChildrenSize > 0 else { return false }

            let estimatedRowHeight: Extended = 1 + spacing
            let buffer: Int = 5 // Load a few items before and after

            let safeHeight = height == .infinity ? 100 : height
            let offsetInt = (offset / estimatedRowHeight).intValue
            let endOffsetInt = ((offset + safeHeight) / estimatedRowHeight).intValue
            
            let startIndex = max(0, offsetInt - buffer)
            let endIndex = min(totalChildrenSize - 1, endOffsetInt + buffer)
            
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
            let estimatedRowHeight: Extended = 1
            let totalHeight = Extended(totalChildrenSize) * estimatedRowHeight + Extended(max(0, totalChildrenSize - 1)) * spacing
            return Size(width: proposedSize.width, height: totalHeight)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            
            let estimatedRowHeight: Extended = 1 + spacing
            
            for control in children {
                // Find index of this control
                var index = 0
                for (i, c) in loadedControls {
                    if c === control {
                        index = i
                        break
                    }
                }
                
                let childSize = control.size(proposedSize: Size(width: size.width, height: .infinity))
                control.layout(size: childSize)
                
                control.layer.frame.position.line = Extended(index) * estimatedRowHeight
                
                switch alignment {
                case .leading: control.layer.frame.position.column = 0
                case .center: control.layer.frame.position.column = (size.width - control.layer.frame.size.width) / 2
                case .trailing: control.layer.frame.position.column = size.width - control.layer.frame.size.width
                }
            }
        }
    }
}
