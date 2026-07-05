import Foundation

@MainActor class Layer {
    private(set) var children: [Layer] = []
    private(set) var parent: Layer?

    weak var content: LayerDrawing?

    var invalidated: Rect?

    weak var renderer: Renderer?

    var frame: Rect = .zero {
        didSet {
            if oldValue != frame {
                parent?.invalidate(rect: oldValue)
                parent?.invalidate(rect: frame)
            }
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
    func invalidate(rect: Rect) {
        if let parent = self.parent {
            parent.invalidate(rect: Rect(position: rect.position + frame.position, size: rect.size))
            return
        }
        renderer?.application?.scheduleUpdate()
        guard let invalidated = self.invalidated else {
            self.invalidated = rect
            return
        }
        self.invalidated = rect.union(invalidated)
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
