import Foundation

@MainActor public struct LazyVGrid<Content: View>: View, PrimitiveView, LayoutRootView {
    public let columns: [GridItem]
    public let alignment: HorizontalAlignment
    public let spacing: Extended?
    public let estimatedRowHeight: Extended
    public let content: Content

    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: Extended? = nil, estimatedRowHeight: Extended = 1, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.estimatedRowHeight = estimatedRowHeight
        self.content = content()
    }

    static var size: Int? { 1 }

    func loadData(node: Node) {
        let control = node.control as! LazyVGridControl
        control.contentNode = node.children[0]
        control.totalChildrenSize = node.children[0].size
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.control = LazyVGridControl(columns: columns, alignment: alignment, spacing: spacing, estimatedRowHeight: estimatedRowHeight)
        node.environment = { _ in }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.control as! LazyVGridControl
        control.columns = columns
        control.alignment = alignment
        control.spacing = spacing
        control.estimatedRowHeight = estimatedRowHeight
        control.totalChildrenSize = node.children[0].size
        control.clearCache()
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
    }

    func insertControl(at index: Int, node: Node) {}
    func removeControl(at index: Int, node: Node) {}

    private class LazyVGridControl: Control, LazyControl {
        var columns: [GridItem]
        var alignment: HorizontalAlignment
        var spacing: Extended?
        var estimatedRowHeight: Extended
        weak var contentNode: Node?
        var totalChildrenSize: Int = 0

        var lastOffset: Extended = 0
        var lastHeight: Extended = 100
        private var lastStartIndex: Int?
        private var lastEndIndex: Int?
        private var lastCalculatedWidth: Extended = -1

        private var loadedControls: [Int: Control] = [:]
        private var calculatedColumns: [(width: Extended, xOffset: Extended, alignment: Alignment?)] = []
        private var rowCount: Int = 0

        func clearCache() {
            loadedControls.removeAll()
            lastStartIndex = nil
            lastEndIndex = nil
            lastCalculatedWidth = -1
        }

        init(columns: [GridItem], alignment: HorizontalAlignment, spacing: Extended?, estimatedRowHeight: Extended) {
            self.columns = columns
            self.alignment = alignment
            self.spacing = spacing
            self.estimatedRowHeight = estimatedRowHeight
        }

        @discardableResult
        override func updateVisibleRegion(offset: Extended, height: Extended) -> Bool {
            lastOffset = offset
            lastHeight = height
            
            guard let contentNode = contentNode, totalChildrenSize > 0 else { return false }

            let rowHeight = estimatedRowHeight
            let verticalSpacing = spacing ?? 0
            let rowTotalHeight = rowHeight + verticalSpacing
            
            let buffer: Int = 2

            let safeHeight = height == .infinity ? 100 : height
            let startRow = max(0, (offset / rowTotalHeight).intValue - buffer)
            let endRow = min(rowCount - 1, ((offset + safeHeight) / rowTotalHeight).intValue + buffer)
            
            if startRow > endRow { return false }
            
            let itemsPerRow = max(1, calculatedColumns.count)
            let startIndex = min(totalChildrenSize - 1, startRow * itemsPerRow)
            let endIndex = min(totalChildrenSize - 1, (endRow + 1) * itemsPerRow - 1)
            
            if startIndex == lastStartIndex && endIndex == lastEndIndex { return false }
            lastStartIndex = startIndex
            lastEndIndex = endIndex
            
            // ── Incremental diff: only remove items that went off-screen ──
            var toRemove: [Int] = []
            for (i, _) in loadedControls {
                if i < startIndex || i > endIndex {
                    toRemove.append(i)
                }
            }
            for i in toRemove {
                if let ctrl = loadedControls[i],
                   let idx = children.firstIndex(where: { $0 === ctrl }) {
                    removeSubview(at: idx)
                }
                loadedControls.removeValue(forKey: i)
            }

            // ── Only add items that are newly visible ──
            for i in startIndex...endIndex {
                if loadedControls[i] == nil {
                    let control = contentNode.control(at: i)
                    loadedControls[i] = control
                    addSubview(control, at: children.count)
                }
            }
            
            layer.invalidate()
            return true
        }




        private func recalculateLayout(availableWidth: Extended) {
            guard availableWidth != lastCalculatedWidth else { return }
            lastCalculatedWidth = availableWidth
            calculatedColumns.removeAll()
            
            var flexIndices: [Int] = []
            var adaptiveGroups: [(index: Int, min: Extended, max: Extended)] = []
            var fixedWidth: Extended = 0
            
            // First pass
            for (i, item) in columns.enumerated() {
                switch item.size {
                case .fixed(let w):
                    calculatedColumns.append((w, 0, item.alignment))
                    fixedWidth += w
                case .flexible:
                    calculatedColumns.append((0, 0, item.alignment))
                    flexIndices.append(i)
                case .adaptive(let minW, let maxW):
                    // Adaptive placeholders
                    calculatedColumns.append((minW, 0, item.alignment))
                    adaptiveGroups.append((i, minW, maxW))
                    fixedWidth += minW
                }
            }
            
            let totalSpacing = spacing ?? 0
            var remainingWidth = max(0, availableWidth - fixedWidth - totalSpacing * Extended(columns.count - 1))
            
            // Handle flexible
            if !flexIndices.isEmpty {
                let w = remainingWidth / Extended(flexIndices.count)
                for idx in flexIndices {
                    calculatedColumns[idx].width = max(10, w) // assume minimum 10 if not set
                }
            } else if !adaptiveGroups.isEmpty {
                // If we have remaining width, we can pack more adaptive columns
                // Actually SwiftUI expands them or repeats them.
                // We'll just expand the first adaptive group to fit more.
                var newCols: [(width: Extended, xOffset: Extended, alignment: Alignment?)] = []
                for (i, item) in columns.enumerated() {
                    if case .adaptive(let minW, _) = item.size {
                        newCols.append((minW, 0, item.alignment))
                        var currentW = minW
                        while remainingWidth >= minW + totalSpacing {
                            newCols.append((minW, 0, item.alignment))
                            remainingWidth -= (minW + totalSpacing)
                            currentW += minW
                        }
                    } else {
                        newCols.append(calculatedColumns[i])
                    }
                }
                calculatedColumns = newCols
            }
            
            // Calculate offsets
            var totalGridWidth: Extended = 0
            for i in 0..<calculatedColumns.count {
                totalGridWidth += calculatedColumns[i].width
            }
            totalGridWidth += Extended(max(0, calculatedColumns.count - 1)) * totalSpacing
            
            var currX: Extended = 0
            switch alignment {
            case .center:
                currX = max(0, (availableWidth - totalGridWidth) / 2)
            case .trailing:
                currX = max(0, availableWidth - totalGridWidth)
            default: // .leading
                break
            }

            for i in 0..<calculatedColumns.count {
                calculatedColumns[i].xOffset = currX
                currX += calculatedColumns[i].width + totalSpacing
            }
            
            let itemsPerRow = max(1, calculatedColumns.count)
            rowCount = Int(ceil(Double(totalChildrenSize) / Double(itemsPerRow)))
        }

        override func size(proposedSize: Size) -> Size {
            recalculateLayout(availableWidth: proposedSize.width)
            let totalHeight = Extended(rowCount) * estimatedRowHeight + Extended(max(0, rowCount - 1)) * (spacing ?? 0)
            return Size(width: proposedSize.width, height: totalHeight)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            recalculateLayout(availableWidth: size.width)
            
            let itemsPerRow = max(1, calculatedColumns.count)
            let rowHeight = estimatedRowHeight
            let verticalSpacing = spacing ?? 0
            
            for control in children {
                var index = 0
                for (i, c) in loadedControls {
                    if c === control {
                        index = i
                        break
                    }
                }
                
                let row = index / itemsPerRow
                let col = index % itemsPerRow
                
                let colSpec = calculatedColumns[col]
                let childSize = control.size(proposedSize: Size(width: colSpec.width, height: rowHeight))
                control.layout(size: childSize)
                
                let yOffset = Extended(row) * (rowHeight + verticalSpacing)
                var xOffset = colSpec.xOffset
                
                // apply alignment
                if let align = colSpec.alignment {
                    switch align.horizontalAlignment {
                    case .leading: break
                    case .center: xOffset += (colSpec.width - childSize.width) / 2
                    case .trailing: xOffset += colSpec.width - childSize.width
                    }
                } else {
                    switch alignment {
                    case .leading: break
                    case .center: xOffset += (colSpec.width - childSize.width) / 2
                    case .trailing: xOffset += colSpec.width - childSize.width
                    }
                }
                
                control.layer.frame.position = Position(column: xOffset, line: yOffset)
            }
        }
    }
}
