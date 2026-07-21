import Foundation

@MainActor class Renderer {
    var layer: Layer
    weak var application: Application?
    var vtRenderer: VTRenderer?

    init(layer: Layer) {
        self.layer = layer
    }

    func update() {
        if let invalidated = layer.invalidated {
            draw(rect: invalidated)
            layer.invalidated = nil
        }
    }

    func draw(rect: Rect? = nil) {
        if rect == nil { layer.invalidated = nil }
        var rect = rect ?? Rect(position: .zero, size: layer.frame.size)
        guard rect.size.width > 0, rect.size.height > 0 else {
            return
        }

        // Repaints must cover whole wide characters. A panel border landing on
        // half of an underlying CJK char blanks the char's other half *outside*
        // the panel frame; when the panel is dismissed the dirty rect is only
        // the panel frame, so without expansion those neighbour cells are never
        // redrawn (missing char halves / stray border glyphs after close).
        rect = expandedToWideCharBounds(rect)

        // When vtRenderer is injected, ScreenBuffer directly maps TUI Cell writes to VTCell.
        var buffer = ScreenBuffer(rect: rect, vtRenderer: vtRenderer)
        layer.draw(into: &buffer)

        // Top-level selection highlight: applied over the final frame so it is
        // always aligned with what is actually on screen (wide characters,
        // overlapping views). Views never draw this themselves.
        application?.window.selectionCoordinator.applyHighlight(into: &buffer)
    }

    /// Inflate a dirty rect by one column on each side, then snap the edges
    /// off wide-char halves in the VT back buffer:
    /// - +1 inflation re-covers cells that an upper layer blanked just outside
    ///   its own frame (straddled CJK lead left of a sheet border);
    /// - left snap: a continuation cell at the edge pulls its lead inside the
    ///   clip, so the redraw can restore the whole glyph;
    /// - right snap: a wide lead at the edge pulls its continuation inside.
    /// Without this, a clipped redraw can never restore straddled halves after
    /// a popover closes.
    private func expandedToWideCharBounds(_ rect: Rect) -> Rect {
        let maxCol = layer.frame.size.width.intValue
        let maxRow = layer.frame.size.height.intValue
        guard maxCol > 0, maxRow > 0 else { return rect }

        var minC = max(0, min(rect.minColumn.intValue, maxCol - 1) - 1)
        var maxC = min(maxCol - 1, max(rect.maxColumn.intValue, 0) + 1)
        let minL = max(0, rect.minLine.intValue)
        let maxL = min(maxRow - 1, rect.maxLine.intValue)
        guard minL <= maxL, minC <= maxC else { return rect }

        if let vt = vtRenderer {
            // A continuation's lead is never itself a continuation, and a wide
            // char is exactly two cells, so each loop moves at most one column
            // per straddling row and terminates quickly.
            var moved = true
            while moved, minC > 0 {
                moved = false
                for line in minL ... maxL
                where vt.back[VTPosition(row: line + 1, column: minC + 1)].character == "\u{0000}" {
                    minC -= 1
                    moved = true
                    break
                }
            }
            moved = true
            while moved, maxC < maxCol - 1 {
                moved = false
                for line in minL ... maxL
                where vt.back[VTPosition(row: line + 1, column: maxC + 1)].character.width > 1 {
                    maxC += 1
                    moved = true
                    break
                }
            }
        }

        return Rect(
            position: Position(column: Extended(minC), line: Extended(minL)),
            size: Size(width: Extended(maxC - minC + 1), height: Extended(maxL - minL + 1))
        )
    }

    func stop() {
        // VTRenderer will restore the terminal when we reset/stop
    }
}
