import Foundation

@MainActor class Layer {
    private(set) var children: [Layer] = []
    private(set) var parent: Layer?

    weak var content: LayerDrawing?

    var invalidated: Rect?

    weak var renderer: Renderer?

    private var suppressFrameInvalidation = false

    var frame: Rect = .zero {
        didSet {
            if !suppressFrameInvalidation, oldValue != frame {
                parent?.invalidate(rect: oldValue)
                parent?.invalidate(rect: frame)
            }
        }
    }

    /// Updates `frame`. When `invalidate` is false, skips the usual old/new frame
    /// dirty propagation (used by ScrollView to move content without dirtying the
    /// full content height).
    func setFrame(_ newFrame: Rect, invalidate: Bool = true) {
        if invalidate {
            frame = newFrame
        } else {
            suppressFrameInvalidation = true
            frame = newFrame
            suppressFrameInvalidation = false
        }
    }

    func addLayer(_ layer: Layer, at index: Int) {
        self.children.insert(layer, at: index)
        layer.parent = self
        self.invalidate(rect: layer.frame)
    }

    func removeLayer(at index: Int) {
        let child = children[index]
        self.invalidate(rect: child.frame)
        child.parent = nil
        self.children.remove(at: index)
    }

    func invalidate() {
        invalidate(rect: Rect(position: .zero, size: frame.size))
    }

    /// This recursively invalidates the same rect in the parent, in the
    /// parent's coordinate system.
    /// If the parent is the root layer, it sets the `invalidated` rect instead.
    /// Dirty rects are clipped to this layer's bounds so clipped children
    /// (e.g. ScrollView content) cannot expand the dirty region beyond the viewport.
    func invalidate(rect: Rect) {
        let bounds = Rect(position: .zero, size: frame.size)
        guard let clipped = rect.intersection(with: bounds) else { return }

        if let parent = self.parent {
            parent.invalidate(rect: Rect(position: clipped.position + frame.position, size: clipped.size))
            return
        }
        renderer?.application?.scheduleUpdate()
        guard let invalidated = self.invalidated else {
            self.invalidated = clipped
            return
        }
        self.invalidated = clipped.union(invalidated)
    }

    func draw(into buffer: inout ScreenBuffer) {
        buffer.saveState()
        buffer.translate(by: frame.position)
        buffer.clip(to: Rect(position: .zero, size: frame.size))
        
        // Draw layer content as background
        content?.draw(into: &buffer)
        
        // Draw children back-to-front
        for child in children {
            child.draw(into: &buffer)
        }
        
        buffer.restoreState()
    }

}
