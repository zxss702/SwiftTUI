import Foundation

@MainActor public struct LazyVGrid<Content: View>: View, PrimitiveView, LayoutRootView {
    public let columns: [GridItem]
    public let alignment: HorizontalAlignment
    public let spacing: Extended?
    public let pinnedViews: PinnedScrollableViews
    public let content: Content

    /// Aligns SwiftUI: `init(columns:alignment:spacing:pinnedViews:content:)`.
    /// Row / section-chrome estimate heights are TUI-internal (default 1).
    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Extended? = nil,
        pinnedViews: PinnedScrollableViews = .init(),
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    static var size: Int? { 1 }

    func loadData(node: Node) {
        let control = node.element as! LazyVGridElement
        control.contentNode = node.children[0]
        control.totalChildrenSize = node.children[0].size
        control.rebuildSectionPlan()
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
    }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        node.element = LazyVGridElement(
            columns: columns,
            alignment: alignment,
            spacing: spacing,
            pinnedViews: pinnedViews
        )
        node.environment = { _ in }
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! LazyVGridElement
        control.columns = columns
        control.alignment = alignment
        control.spacing = spacing
        control.pinnedViews = pinnedViews
        if control.reloadContent(totalChildrenSize: node.children[0].size) {
            node.root.application?.requestLayout()
        }
    }

    func insertElement(at index: Int, node: Node) {
        (node.element as! LazyVGridElement).handleInsert(at: index)
    }

    func removeElement(at index: Int, node: Node) {
        (node.element as! LazyVGridElement).handleRemove(at: index)
    }

    // MARK: - Element

    private class LazyVGridElement: Element, LazyElement {
        var columns: [GridItem]
        var alignment: HorizontalAlignment
        var spacing: Extended?
        var pinnedViews: PinnedScrollableViews
        /// Internal lazy estimate (not part of public API).
        let estimatedRowHeight: Extended = 1
        let estimatedSectionChromeHeight: Extended = 1
        weak var contentNode: Node?
        var totalChildrenSize: Int = 0

        var lastOffset: Extended = 0
        var lastHeight: Extended = 100
        private var lastStartIndex: Int?
        private var lastEndIndex: Int?
        private var lastForcedChrome: Set<Int> = []
        private var lastCalculatedWidth: Extended = -1

        private var loadedElements: [Int: Element] = [:]
        private var calculatedColumns: [(width: Extended, xOffset: Extended, alignment: Alignment?)] = []

        /// Per flat-index kind derived from Section nodes.
        private var itemKinds: [ItemKind] = []
        private var sections: [SectionBand] = []
        /// Natural (unpinned) Y origin for each flat index.
        private var naturalY: [Extended] = []
        private var contentHeight: Extended = 0

        private enum ItemKind {
            case cell
            case header
            case footer
        }

        private struct SectionBand {
            var headerIndex: Int?
            var cellIndices: [Int] = []
            var footerIndex: Int?
            var startY: Extended = 0
            var endY: Extended = 0
        }

        init(
            columns: [GridItem],
            alignment: HorizontalAlignment,
            spacing: Extended?,
            pinnedViews: PinnedScrollableViews
        ) {
            self.columns = columns
            self.alignment = alignment
            self.spacing = spacing
            self.pinnedViews = pinnedViews
        }

        func clearCache() {
            unloadAllLoadedElements()
            lastStartIndex = nil
            lastEndIndex = nil
            lastForcedChrome = []
            lastCalculatedWidth = -1
            itemKinds = []
            sections = []
            naturalY = []
            contentHeight = 0
        }

        @discardableResult
        func reloadContent(totalChildrenSize: Int) -> Bool {
            self.totalChildrenSize = totalChildrenSize
            var remounted = false
            var toRemove: [Int] = []
            for (i, _) in loadedElements where i >= totalChildrenSize {
                toRemove.append(i)
            }
            for i in toRemove {
                unloadElement(at: i)
                remounted = true
            }
            if let contentNode {
                let swappingIdentity = loadedElements.contains { i, ctrl in
                    contentNode.element(at: i) !== ctrl
                }
                // Same-index identity swap (footer gains/loses Menu) must not
                // synthesize onHover(false) — Application re-resolves hover after layout.
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
            lastForcedChrome = []
            rebuildSectionPlan()
            updateVisibleRegion(offset: lastOffset, height: lastHeight)
            return remounted
        }

        func handleInsert(at index: Int) {
            totalChildrenSize += 1
            for key in loadedElements.keys.filter({ $0 >= index }).sorted(by: >) {
                if let ctrl = loadedElements.removeValue(forKey: key) {
                    loadedElements[key + 1] = ctrl
                }
            }
            lastStartIndex = nil
            lastEndIndex = nil
            lastForcedChrome = []
        }

        func handleRemove(at index: Int) {
            totalChildrenSize = max(0, totalChildrenSize - 1)
            unloadElement(at: index)
            for key in loadedElements.keys.filter({ $0 > index }).sorted() {
                if let ctrl = loadedElements.removeValue(forKey: key) {
                    loadedElements[key - 1] = ctrl
                }
            }
            lastStartIndex = nil
            lastEndIndex = nil
            lastForcedChrome = []
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
        }

        // MARK: Section plan

        func rebuildSectionPlan() {
            itemKinds = []
            sections = []
            naturalY = []
            contentHeight = 0

            guard let contentNode, totalChildrenSize > 0 else { return }

            contentNode.build()
            collectKinds(from: contentNode, into: &itemKinds)

            // Fallback: if walker produced nothing but we have children, treat all as cells.
            if itemKinds.isEmpty {
                itemKinds = Array(repeating: .cell, count: max(totalChildrenSize, 0))
            } else {
                // 以 walker 为准：惰性 ForEach 的 Node.size 在展开前可能与扁平控件数不一致。
                totalChildrenSize = itemKinds.count
            }

            buildSectionsFromKinds()
            recalculateNaturalPositions()
        }

        private func collectKinds(from node: Node, into kinds: inout [ItemKind]) {
            node.build()

            if node.view is SectionLayoutView {
                // Section children: 0 header chrome, 1 content, 2 footer chrome
                guard node.children.count >= 3 else { return }
                appendChromeKinds(from: node.children[0], role: .header, into: &kinds)
                collectKinds(from: node.children[1], into: &kinds)
                appendChromeKinds(from: node.children[2], role: .footer, into: &kinds)
                return
            }

            // 惰性 ForEach：children 为空，按 data 槽位 ensure 后递归（展开 Section 等）。
            if let source = node.view as? ContiguousChildSource {
                let slots = source.dataCount(node: node)
                for i in 0 ..< slots {
                    collectKinds(from: source.childNode(node: node, at: i), into: &kinds)
                }
                return
            }

            // Leaf / layout root with its own control → one cell
            if node.element != nil {
                kinds.append(.cell)
                return
            }

            // Structural / composed: recurse
            if node.children.isEmpty {
                return
            }
            for child in node.children {
                collectKinds(from: child, into: &kinds)
            }
        }

        private func appendChromeKinds(from node: Node, role: ItemKind, into kinds: inout [ItemKind]) {
            let count = node.size
            for _ in 0 ..< count {
                kinds.append(role)
            }
        }

        private func buildSectionsFromKinds() {
            sections = []
            var current = SectionBand()
            var hasContent = false

            for (i, kind) in itemKinds.enumerated() {
                switch kind {
                case .header:
                    if hasContent {
                        sections.append(current)
                        current = SectionBand()
                        hasContent = false
                    }
                    current.headerIndex = i
                    hasContent = true
                case .cell:
                    current.cellIndices.append(i)
                    hasContent = true
                case .footer:
                    current.footerIndex = i
                    sections.append(current)
                    current = SectionBand()
                    hasContent = false
                }
            }
            if hasContent {
                sections.append(current)
            }
        }

        private func estimatedHeight(for kind: ItemKind) -> Extended {
            switch kind {
            case .cell: return estimatedRowHeight
            case .header, .footer: return estimatedSectionChromeHeight
            }
        }

        private func recalculateNaturalPositions() {
            naturalY = Array(repeating: 0, count: totalChildrenSize)
            let verticalSpacing = spacing ?? 0
            let itemsPerRow = max(1, calculatedColumns.isEmpty ? columns.count : calculatedColumns.count)
            var y: Extended = 0

            for section in sections.indices {
                var band = sections[section]
                band.startY = y

                if let headerIndex = band.headerIndex {
                    naturalY[headerIndex] = y
                    y += estimatedHeight(for: .header) + verticalSpacing
                }

                let cells = band.cellIndices
                if !cells.isEmpty {
                    let rowCount = Int(ceil(Double(cells.count) / Double(itemsPerRow)))
                    for (offset, index) in cells.enumerated() {
                        let row = offset / itemsPerRow
                        naturalY[index] = y + Extended(row) * (estimatedRowHeight + verticalSpacing)
                    }
                    y += Extended(rowCount) * estimatedRowHeight
                        + Extended(max(0, rowCount - 1)) * verticalSpacing
                    if band.footerIndex != nil || section < sections.count - 1 {
                        y += verticalSpacing
                    }
                }

                if let footerIndex = band.footerIndex {
                    naturalY[footerIndex] = y
                    y += estimatedHeight(for: .footer)
                    if section < sections.count - 1 {
                        y += verticalSpacing
                    }
                }

                band.endY = y
                sections[section] = band
            }

            // No-section fallback: pure grid of cells
            if sections.isEmpty && totalChildrenSize > 0 {
                let rowCount = Int(ceil(Double(totalChildrenSize) / Double(itemsPerRow)))
                for i in 0 ..< totalChildrenSize {
                    let row = i / itemsPerRow
                    naturalY[i] = Extended(row) * (estimatedRowHeight + verticalSpacing)
                }
                contentHeight = Extended(rowCount) * estimatedRowHeight
                    + Extended(max(0, rowCount - 1)) * verticalSpacing
            } else {
                contentHeight = y
            }
        }

        private func pinnedY(for index: Int, kind: ItemKind, viewportTop: Extended, viewportBottom: Extended) -> Extended {
            let natural = index < naturalY.count ? naturalY[index] : 0
            let h = estimatedHeight(for: kind)

            guard let section = sections.first(where: {
                $0.headerIndex == index || $0.footerIndex == index || $0.cellIndices.contains(index)
            }) else {
                return natural
            }

            switch kind {
            case .header where pinnedViews.contains(.sectionHeaders):
                // Only the section that owns the viewport top edge may stick.
                // Otherwise every intersecting section's header collapses onto the same row.
                guard isHeaderPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom) else {
                    return natural
                }
                let maxY = max(section.startY, section.endY - h)
                return min(max(natural, viewportTop), maxY)
            case .footer where pinnedViews.contains(.sectionFooters):
                // Only the section that owns the viewport bottom edge may stick.
                guard isFooterPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom) else {
                    return natural
                }
                let minY = section.startY
                let ideal = viewportBottom - h
                return min(max(ideal, minY), natural)
            default:
                return natural
            }
        }

        /// Section whose sticky header should occupy the top of the viewport.
        private func isHeaderPinOwner(
            _ section: SectionBand,
            viewportTop: Extended,
            viewportBottom: Extended
        ) -> Bool {
            guard section.headerIndex != nil else { return false }
            // Prefer the last section that still covers the top edge (matches SwiftUI):
            // while scrolling through a section, that section owns the top until it leaves.
            let topRow = viewportTop
            if let owner = sections.last(where: { $0.startY <= topRow && $0.endY > topRow }) {
                return owner.headerIndex == section.headerIndex
            }
            // Fallback: last intersecting section.
            if let owner = sections.last(where: {
                $0.endY > viewportTop && $0.startY < viewportBottom && $0.headerIndex != nil
            }) {
                return owner.headerIndex == section.headerIndex
            }
            return false
        }

        /// Section whose sticky footer should occupy the bottom of the viewport.
        private func isFooterPinOwner(
            _ section: SectionBand,
            viewportTop: Extended,
            viewportBottom: Extended
        ) -> Bool {
            guard section.footerIndex != nil else { return false }
            let bottomRow = max(viewportTop, viewportBottom - 1)
            if let owner = sections.last(where: { $0.startY <= bottomRow && $0.endY > bottomRow }) {
                return owner.footerIndex == section.footerIndex
            }
            if let owner = sections.last(where: {
                $0.endY > viewportTop && $0.startY < viewportBottom && $0.footerIndex != nil
            }) {
                return owner.footerIndex == section.footerIndex
            }
            return false
        }

        // MARK: Visible region

        @discardableResult
        override func updateVisibleRegion(offset: Extended, height: Extended) -> Bool {
            lastOffset = offset
            lastHeight = height

            guard let contentNode = contentNode, totalChildrenSize > 0 else { return false }

            if itemKinds.count != totalChildrenSize {
                rebuildSectionPlan()
            }

            let buffer: Int = 2
            let safeHeight = height == .infinity ? 100 : height
            let viewportTop = offset
            let viewportBottom = offset + safeHeight

            var startIndex = 0
            var endIndex = totalChildrenSize - 1

            // Find first/last index whose natural frame intersects the viewport (+ buffer rows).
            let rowStep = estimatedRowHeight + (spacing ?? 0)
            let bufferPx = Extended(buffer) * rowStep
            let lo = offset - bufferPx
            let hi = offset + safeHeight + bufferPx

            if !naturalY.isEmpty {
                startIndex = 0
                for i in 0 ..< totalChildrenSize {
                    let kind = itemKinds.indices.contains(i) ? itemKinds[i] : .cell
                    let bottom = naturalY[i] + estimatedHeight(for: kind)
                    if bottom >= lo {
                        startIndex = i
                        break
                    }
                }
                endIndex = totalChildrenSize - 1
                for i in stride(from: totalChildrenSize - 1, through: 0, by: -1) {
                    if naturalY[i] <= hi {
                        endIndex = i
                        break
                    }
                }
            }

            if startIndex > endIndex { return false }

            // Force-load at most one sticky header and one sticky footer (viewport owners).
            var forcedChrome: Set<Int> = []
            for section in sections {
                if pinnedViews.contains(.sectionHeaders),
                   let h = section.headerIndex,
                   isHeaderPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom)
                {
                    forcedChrome.insert(h)
                }
                if pinnedViews.contains(.sectionFooters),
                   let f = section.footerIndex,
                   isFooterPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom)
                {
                    forcedChrome.insert(f)
                }
            }

            if startIndex == lastStartIndex,
               endIndex == lastEndIndex,
               forcedChrome == lastForcedChrome {
                return false
            }
            lastStartIndex = startIndex
            lastEndIndex = endIndex
            lastForcedChrome = forcedChrome

            var needed = Set(startIndex ... endIndex)
            needed.formUnion(forcedChrome)

            var toRemove: [Int] = []
            for (i, _) in loadedElements where !needed.contains(i) {
                toRemove.append(i)
            }
            for i in toRemove {
                unloadElement(at: i)
            }

            for i in needed.sorted() {
                if loadedElements[i] == nil {
                    let control = contentNode.element(at: i)
                    if control.parent == nil {
                        loadedElements[i] = control
                        addSubview(control, at: children.count)
                    } else if control.parent === self {
                        loadedElements[i] = control
                    } else {
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

        // MARK: Column math

        private func recalculateLayout(availableWidth: Extended) {
            guard availableWidth != lastCalculatedWidth else { return }
            lastCalculatedWidth = availableWidth
            calculatedColumns.removeAll()

            var flexIndices: [Int] = []
            var adaptiveGroups: [(index: Int, min: Extended, max: Extended)] = []
            var fixedWidth: Extended = 0

            for (i, item) in columns.enumerated() {
                switch item.size {
                case .fixed(let w):
                    calculatedColumns.append((w, 0, item.alignment))
                    fixedWidth += w
                case .flexible:
                    calculatedColumns.append((0, 0, item.alignment))
                    flexIndices.append(i)
                case .adaptive(let minW, let maxW):
                    calculatedColumns.append((minW, 0, item.alignment))
                    adaptiveGroups.append((i, minW, maxW))
                    fixedWidth += minW
                }
            }

            let totalSpacing = spacing ?? 0
            var remainingWidth = max(0, availableWidth - fixedWidth - totalSpacing * Extended(columns.count - 1))

            if !flexIndices.isEmpty {
                let w = remainingWidth / Extended(flexIndices.count)
                for idx in flexIndices {
                    calculatedColumns[idx].width = max(10, w)
                }
            } else if !adaptiveGroups.isEmpty {
                var newCols: [(width: Extended, xOffset: Extended, alignment: Alignment?)] = []
                for (i, item) in columns.enumerated() {
                    if case .adaptive(let minW, _) = item.size {
                        newCols.append((minW, 0, item.alignment))
                        while remainingWidth >= minW + totalSpacing {
                            newCols.append((minW, 0, item.alignment))
                            remainingWidth -= (minW + totalSpacing)
                        }
                    } else {
                        newCols.append(calculatedColumns[i])
                    }
                }
                calculatedColumns = newCols
            }

            var totalGridWidth: Extended = 0
            for i in 0 ..< calculatedColumns.count {
                totalGridWidth += calculatedColumns[i].width
            }
            totalGridWidth += Extended(max(0, calculatedColumns.count - 1)) * totalSpacing

            var currX: Extended = 0
            switch alignment {
            case .center:
                currX = max(0, (availableWidth - totalGridWidth) / 2)
            case .trailing:
                currX = max(0, availableWidth - totalGridWidth)
            default:
                break
            }

            for i in 0 ..< calculatedColumns.count {
                calculatedColumns[i].xOffset = currX
                currX += calculatedColumns[i].width + totalSpacing
            }

            // Column count change affects row packing — rebuild Y positions.
            recalculateNaturalPositions()
        }

        override func size(proposedSize: Size) -> Size {
            recalculateLayout(availableWidth: proposedSize.width)
            if itemKinds.count != totalChildrenSize {
                rebuildSectionPlan()
            } else {
                recalculateNaturalPositions()
            }
            return Size(width: proposedSize.width, height: contentHeight)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            recalculateLayout(availableWidth: size.width)

            if itemKinds.count != totalChildrenSize {
                rebuildSectionPlan()
            }

            let itemsPerRow = max(1, calculatedColumns.count)
            let viewportTop = lastOffset
            let viewportBottom = lastOffset + (lastHeight == .infinity ? size.height : lastHeight)

            // Layout cells first, then pinned chrome on top (later subviews draw later if z equal —
            // move pinned chrome to end of children for paint order).
            var chromeIndices: [Int] = []

            for (index, control) in loadedElements {
                let kind = itemKinds.indices.contains(index) ? itemKinds[index] : .cell
                let y = pinnedY(for: index, kind: kind, viewportTop: viewportTop, viewportBottom: viewportBottom)

                switch kind {
                case .header, .footer:
                    chromeIndices.append(index)
                    let childSize = control.size(proposedSize: Size(width: size.width, height: estimatedHeight(for: kind)))
                    control.layout(size: Size(width: size.width, height: childSize.height))
                    control.layer.frame.position = Position(column: 0, line: y)
                case .cell:
                    let cellOffset: Int
                    if let section = sections.first(where: { $0.cellIndices.contains(index) }),
                       let local = section.cellIndices.firstIndex(of: index) {
                        cellOffset = local
                    } else {
                        cellOffset = index
                    }
                    let col = cellOffset % itemsPerRow
                    let colSpec = calculatedColumns[col]
                    let childSize = control.size(proposedSize: Size(width: colSpec.width, height: estimatedRowHeight))
                    control.layout(size: childSize)

                    var xOffset = colSpec.xOffset
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
                    control.layer.frame.position = Position(column: xOffset, line: y)
                }
            }

            // Raise only viewport-owned sticky chrome so draw/hit-test stays above
            // cells — do NOT lift every loaded footer (that stacked footers in the
            // same paint layer and stole hover from natural-position footers).
            let pinOwners: Set<Int> = {
                var owners: Set<Int> = []
                for section in sections {
                    if pinnedViews.contains(.sectionHeaders),
                       let h = section.headerIndex,
                       isHeaderPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom)
                    {
                        owners.insert(h)
                    }
                    if pinnedViews.contains(.sectionFooters),
                       let f = section.footerIndex,
                       isFooterPinOwner(section, viewportTop: viewportTop, viewportBottom: viewportBottom)
                    {
                        owners.insert(f)
                    }
                }
                return owners
            }()
            for index in chromeIndices where pinOwners.contains(index) {
                guard let control = loadedElements[index],
                      let idx = children.firstIndex(where: { $0 === control }) else { continue }
                if idx != children.count - 1 {
                    removeSubview(at: idx)
                    addSubview(control, at: children.count)
                }
            }
        }
    }
}
