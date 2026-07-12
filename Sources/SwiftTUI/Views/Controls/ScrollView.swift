import Foundation

/// Automatically scrolls to the currently active control. The content needs to contain controls
/// such as buttons to scroll to.
@MainActor public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: VStack<Content>

    public init(@ViewBuilder _ content: () -> Content) {
        self.content = VStack(content: content())
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        let control = ScrollControl()
        control.contentControl = node.children[0].control(at: 0)
        control.addSubview(control.contentControl, at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
    }

    private class ScrollControl: Control, ScrollToIdentityBridging {
        var contentControl: Control!
        /// Cached content size from the last full layout; used to clamp scroll without re-measuring.
        var cachedContentSize: Size = .zero
        var contentOffset: Extended = 0

        func scrollToIdentity(_ id: AnyHashable) {
            guard let target = findIdentity(id, in: contentControl) else { return }
            let absolute = target.absoluteFrame.position.line
            let contentOrigin = contentControl.absoluteFrame.position.line
            let destination = absolute - contentOrigin
            contentOffset = destination
            applyScrollOffset()
        }

        private func findIdentity(_ id: AnyHashable, in control: Control) -> IdentityAnchorControl? {
            if let anchor = control as? IdentityAnchorControl, anchor.id == id {
                return anchor
            }
            for child in control.children {
                if let found = findIdentity(id, in: child) { return found }
            }
            return nil
        }

        /// 默认占满全部高度，顶部对齐（对齐 SwiftUI）。
        override func size(proposedSize: Size) -> Size {
            let contentSize = contentControl.size(
                proposedSize: Size(width: proposedSize.width, height: .infinity)
            )
            let height: Extended
            if proposedSize.height == .infinity {
                height = contentSize.height
            } else {
                height = proposedSize.height
            }
            let width: Extended
            if proposedSize.width == .infinity {
                width = contentSize.width
            } else {
                width = min(max(contentSize.width, 1), proposedSize.width)
            }
            return Size(width: width, height: height)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            var contentSize = contentControl.size(proposedSize: Size(width: size.width, height: .infinity))
            // Viewport or content height may have changed (e.g. window resize);
            // re-clamp so a previous "scrolled to bottom" offset does not leave
            // the bottom content floating in the middle of a taller viewport.
            var maxOffset = max(Extended(0), contentSize.height - size.height)
            contentOffset = min(max(Extended(0), contentOffset), maxOffset)
            contentControl.updateVisibleRegion(offset: contentOffset, height: size.height)
            contentControl.layout(size: contentSize)

            // Lazy stacks measure real row heights during layout; content size may grow.
            // Refine once so ScrollView's scroll range matches wrapped multi-line rows.
            let refined = contentControl.size(proposedSize: Size(width: size.width, height: .infinity))
            if refined.height != contentSize.height || refined.width != contentSize.width {
                contentSize = refined
                maxOffset = max(Extended(0), contentSize.height - size.height)
                contentOffset = min(max(Extended(0), contentOffset), maxOffset)
                contentControl.updateVisibleRegion(offset: contentOffset, height: size.height)
                contentControl.layout(size: contentSize)
            }
            cachedContentSize = contentSize
            applyContentOffset(invalidateLayer: true)
        }

        override func scroll(to position: Position) {
            let destination = position.line - contentControl.layer.frame.position.line
            guard layer.frame.size.height > 0 else { return }
            let previous = contentOffset
            if contentOffset > destination {
                contentOffset = destination
            } else if contentOffset < destination - layer.frame.size.height + 1 {
                contentOffset = destination - layer.frame.size.height + 1
            }
            if contentOffset != previous {
                applyScrollOffset()
            }
        }

        override func handleMouseEvent(_ event: MouseEvent) {
            if case .scroll(_, let deltaY) = event.type {
                contentOffset += Extended(deltaY)
                applyScrollOffset()
            } else {
                super.handleMouseEvent(event)
            }
        }

        /// Clamps offset, updates lazy visible region, optionally lays out, then moves content.
        private func applyScrollOffset() {
            let viewportHeight = layer.frame.size.height
            let maxOffset = max(Extended(0), cachedContentSize.height - viewportHeight)
            contentOffset = min(max(Extended(0), contentOffset), maxOffset)

            let lazyNeedsLayout = contentControl.updateVisibleRegion(
                offset: contentOffset,
                height: viewportHeight
            )
            if lazyNeedsLayout {
                contentControl.layout(size: cachedContentSize)
                let refined = contentControl.size(
                    proposedSize: Size(width: layer.frame.size.width, height: .infinity)
                )
                if refined.height != cachedContentSize.height || refined.width != cachedContentSize.width {
                    cachedContentSize = refined
                    let refinedMax = max(Extended(0), cachedContentSize.height - viewportHeight)
                    contentOffset = min(max(Extended(0), contentOffset), refinedMax)
                    contentControl.updateVisibleRegion(offset: contentOffset, height: viewportHeight)
                    contentControl.layout(size: cachedContentSize)
                }
            }

            applyContentOffset(invalidateLayer: false)
            layer.invalidate()
        }

        private func applyContentOffset(invalidateLayer: Bool) {
            var contentFrame = contentControl.layer.frame
            contentFrame.position.line = -contentOffset
            contentControl.layer.setFrame(contentFrame, invalidate: invalidateLayer)
        }
    }
}
