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
        setupEnvironmentProperties(node: node)
        node.addNode(at: 0, Node(view: content.view))
        let control = ScrollElement()
        control.contentElement = node.children[0].element(at: 0)
        control.addSubview(control.contentElement, at: 0)
        node.element = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        node.children[0].update(using: content.view)
        let control = node.element as! ScrollElement
        let newContent = node.children[0].element(at: 0)
        control.contentElement = newContent
        control.syncChild(newContent)
    }

    private class ScrollElement: Element, ScrollToIdentityBridging {
        var contentElement: Element!
        /// Cached content size from the last full layout; used to clamp scroll without re-measuring.
        var cachedContentSize: Size = .zero
        var contentOffset: Extended = 0

        func scrollToIdentity(_ id: AnyHashable, anchor: UnitPoint?) {
            pendingScroll = PendingScroll(id: id, anchor: anchor)
            // Avoid re-entering layout from `onAppear` / child layout callbacks.
            if !isLayingOut {
                applyPendingScroll()
            }
        }

        private struct PendingScroll {
            var id: AnyHashable
            var anchor: UnitPoint?
        }

        private var pendingScroll: PendingScroll?
        private var isLayingOut = false

        private static func offset(
            contentY: Extended,
            targetHeight: Extended,
            viewportHeight: Extended,
            anchor: UnitPoint?
        ) -> Extended {
            // nil → top: put the target's top edge at the viewport top.
            let a = anchor ?? .top
            let span = viewportHeight - targetHeight
            let shift = Extended(Int((a.y * Double(span.intValue)).rounded()))
            return contentY - shift
        }

        private func applyPendingScroll() {
            guard let pending = pendingScroll else { return }
            let viewport = layer.frame.size.height
            guard viewport > 0 else { return }
            // Re-resolve the target position now that layout is complete, so
            // that calls originating from `onAppear` (fired during super.layout)
            // use fresh absoluteFrame coordinates rather than pre-layout values.
            let contentY: Extended
            let targetHeight: Extended
            if let target = ScrollIdentityLookup.findIdentity(pending.id, in: contentElement) {
                let contentOrigin = contentElement.absoluteFrame.position.line
                contentY = target.absoluteFrame.position.line - contentOrigin
                targetHeight = max(Extended(1), target.absoluteFrame.size.height)
            } else if let estimated = ScrollIdentityLookup.lazyContentOffset(for: pending.id, in: contentElement) {
                contentY = estimated
                targetHeight = 1
            } else {
                return
            }
            pendingScroll = nil
            contentOffset = Self.offset(
                contentY: contentY,
                targetHeight: targetHeight,
                viewportHeight: viewport,
                anchor: pending.anchor
            )
            applyScrollOffset()
        }

        /// 默认占满全部高度，顶部对齐（对齐 SwiftUI）。
        override func size(proposedSize: Size) -> Size {
            let contentSize = contentElement.size(
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
            isLayingOut = true
            defer {
                isLayingOut = false
                applyPendingScroll()
            }
            super.layout(size: size)
            var contentSize = contentElement.size(proposedSize: Size(width: size.width, height: .infinity))
            // Viewport or content height may have changed (e.g. window resize);
            // re-clamp so a previous "scrolled to bottom" offset does not leave
            // the bottom content floating in the middle of a taller viewport.
            var maxOffset = max(Extended(0), contentSize.height - size.height)
            contentOffset = min(max(Extended(0), contentOffset), maxOffset)
            contentElement.updateVisibleRegion(offset: contentOffset, height: size.height)
            contentElement.layout(size: contentSize)

            // Lazy stacks measure real row heights during layout; content size may grow.
            // Refine once so ScrollView's scroll range matches wrapped multi-line rows.
            let refined = contentElement.size(proposedSize: Size(width: size.width, height: .infinity))
            if refined.height != contentSize.height || refined.width != contentSize.width {
                contentSize = refined
                maxOffset = max(Extended(0), contentSize.height - size.height)
                contentOffset = min(max(Extended(0), contentOffset), maxOffset)
                contentElement.updateVisibleRegion(offset: contentOffset, height: size.height)
                contentElement.layout(size: contentSize)
            }
            cachedContentSize = contentSize
            applyContentOffset(invalidateLayer: true)
        }

        override func scroll(to position: Position) {
            let destination = position.line - contentElement.layer.frame.position.line
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

        override func consumeMouseEvent(_ event: MouseEvent) -> Bool {
            if case .scroll(_, let deltaY) = event.type {
                contentOffset += Extended(deltaY)
                applyScrollOffset()
                return true
            }
            return false
        }

        override var scrollViewportAbsoluteFrame: Rect? { absoluteFrame }

        /// Clamps offset, updates lazy visible region, optionally lays out, then moves content.
        private func applyScrollOffset() {
            let viewportHeight = layer.frame.size.height
            let maxOffset = max(Extended(0), cachedContentSize.height - viewportHeight)
            contentOffset = min(max(Extended(0), contentOffset), maxOffset)

            let lazyNeedsLayout = contentElement.updateVisibleRegion(
                offset: contentOffset,
                height: viewportHeight
            )
            if lazyNeedsLayout {
                contentElement.layout(size: cachedContentSize)
                let refined = contentElement.size(
                    proposedSize: Size(width: layer.frame.size.width, height: .infinity)
                )
                if refined.height != cachedContentSize.height || refined.width != cachedContentSize.width {
                    cachedContentSize = refined
                    let refinedMax = max(Extended(0), cachedContentSize.height - viewportHeight)
                    contentOffset = min(max(Extended(0), contentOffset), refinedMax)
                    contentElement.updateVisibleRegion(offset: contentOffset, height: viewportHeight)
                    contentElement.layout(size: cachedContentSize)
                }
            }

            applyContentOffset(invalidateLayer: false)
            layer.invalidate()
        }

        private func applyContentOffset(invalidateLayer: Bool) {
            var contentFrame = contentElement.layer.frame
            contentFrame.position.line = -contentOffset
            contentElement.layer.setFrame(contentFrame, invalidate: invalidateLayer)
        }
    }
}
