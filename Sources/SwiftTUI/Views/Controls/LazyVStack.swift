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
        control.totalChildrenSize = node.children[0].size
        control.clearCache() // Clear cache so views are recreated correctly on update
        control.updateVisibleRegion(offset: control.lastOffset, height: control.lastHeight)
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
            loadedControls.removeAll()
            lastStartIndex = nil
            lastEndIndex = nil
        }

        init(alignment: HorizontalAlignment, spacing: Extended) {
            self.alignment = alignment
            self.spacing = spacing
        }

        override func updateVisibleRegion(offset: Extended, height: Extended) {
            lastOffset = offset
            lastHeight = height
            
            guard let contentNode = contentNode, totalChildrenSize > 0 else { return }

            let estimatedRowHeight: Extended = 1 + spacing
            let buffer: Int = 5 // Load a few items before and after

            let safeHeight = height == .infinity ? 100 : height
            let offsetInt = (offset / estimatedRowHeight).intValue
            let endOffsetInt = ((offset + safeHeight) / estimatedRowHeight).intValue
            
            let startIndex = max(0, offsetInt - buffer)
            let endIndex = min(totalChildrenSize - 1, endOffsetInt + buffer)
            
            if startIndex > endIndex { return }
            if startIndex == lastStartIndex && endIndex == lastEndIndex { return }
            lastStartIndex = startIndex
            lastEndIndex = endIndex
            
            // Rebuild children
            for i in (0 ..< children.count).reversed() {
                removeSubview(at: i)
            }
            
            var newLoaded: [Int: Control] = [:]
            for i in startIndex...endIndex {
                if let existing = loadedControls[i] {
                    newLoaded[i] = existing
                } else {
                    let control = contentNode.control(at: i)
                    newLoaded[i] = control
                }
            }
            loadedControls = newLoaded
            
            for i in startIndex...endIndex {
                if let control = loadedControls[i] {
                    addSubview(control, at: children.count)
                }
            }
            
            layer.invalidate()
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
