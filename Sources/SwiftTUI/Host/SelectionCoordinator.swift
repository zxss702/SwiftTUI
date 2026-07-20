import Foundation

/// Shared visual style for text selections (macOS-like light blue).
///
/// Terminals have no alpha blending, so the highlight also forces a dark
/// foreground — otherwise light-on-light text would be unreadable in dark
/// themes.
@MainActor
enum TextSelectionStyle {
    static let background = Color.trueColor(red: 179, green: 215, blue: 255)
    static let foreground = Color.trueColor(red: 20, green: 20, blue: 20)
}

/// Selection geometry published by a `.selectable()` region to the top-level
/// highlight pass (a preference-style upward channel: the region reports its
/// absolute frame + local selection, the renderer consumes it after the whole
/// layer tree has drawn).
struct SelectionHighlightRegion {
    /// Absolute screen frame of the selectable region.
    let frame: Rect
    /// Selection start in region-local coordinates (inclusive).
    let start: Position
    /// Selection end in region-local coordinates (inclusive).
    let end: Position
    /// Region-local rects excluded from selection (`.selectionDisabled()`
    /// subtrees, e.g. line-number gutters): never highlighted, never copied.
    var maskedRects: [Rect] = []

    /// Whether a region-local cell is covered by a `.selectionDisabled()` area.
    func isMasked(column: Int, row: Int) -> Bool {
        guard !maskedRects.isEmpty else { return false }
        let position = Position(column: Extended(column), line: Extended(row))
        return maskedRects.contains { $0.contains(position) }
    }

    /// Selected column range for a local row, or `nil` when the row is
    /// outside the selection. Terminal linear-selection convention: first row
    /// from the start column, middle rows full width, last row up to the end
    /// column (inclusive).
    func selectedColumns(inRow row: Int) -> Range<Int>? {
        let startLine = start.line.intValue
        let endLine = end.line.intValue
        guard row >= startLine, row <= endLine else { return nil }
        let width = max(1, frame.size.width.intValue)
        let lower = row == startLine ? start.column.intValue : 0
        let upper = row == endLine ? end.column.intValue + 1 : width
        guard lower < upper else { return nil }
        return lower ..< upper
    }
}

/// Anything that can own a text selection (`.selectable()` regions,
/// TextField, SecureField, TextEditor).
@MainActor
protocol SelectionOwner: AnyObject {
    /// Remove the selection and repaint the affected area.
    func clearSelection()
    /// The currently selected text, or `nil` when nothing is selected.
    func selectedText() -> String?
    /// Geometry for the global highlight pass, or `nil` for owners that
    /// render their own highlight (text editors).
    func selectionHighlightRegion() -> SelectionHighlightRegion?
    /// Called by the highlight pass with the characters currently visible in
    /// a selected region row (region-local row, full region width; positions
    /// not covered by this draw are `nil`).
    func captureVisibleRow(_ row: Int, characters: [Character?])
}

extension SelectionOwner {
    func selectionHighlightRegion() -> SelectionHighlightRegion? { nil }
    func captureVisibleRow(_ row: Int, characters: [Character?]) {}
}

/// Application-wide selection registry: at most one active selection exists
/// at any time. Starting a new selection automatically clears the previous
/// owner's selection.
@MainActor
final class SelectionCoordinator {
    private weak var owner: (any SelectionOwner)?

    var activeOwner: (any SelectionOwner)? { owner }

    /// Registers `owner` as the active selection holder, clearing any other
    /// owner's selection first.
    func begin(_ owner: any SelectionOwner) {
        if let current = self.owner, current !== owner {
            current.clearSelection()
        }
        self.owner = owner
    }

    /// Unregisters `owner` without touching its selection state.
    func end(_ owner: any SelectionOwner) {
        if self.owner === owner {
            self.owner = nil
        }
    }

    /// Clears the active selection (if any) and unregisters its owner.
    func clearActiveSelection() {
        owner?.clearSelection()
        owner = nil
    }

    // MARK: - Global highlight pass

    /// Applies the active region selection on top of the freshly drawn
    /// buffer (called by the renderer after the whole layer tree painted,
    /// before present). Working on the final buffer guarantees the highlight
    /// is aligned with what is actually on screen — including wide (CJK /
    /// emoji) characters — and keeps the selection layer out of the views.
    ///
    /// Also captures the visible characters of each selected row so the
    /// copied text survives rows scrolling out during edge auto-scroll.
    func applyHighlight(into buffer: inout ScreenBuffer) {
        guard let owner, let region = owner.selectionHighlightRegion() else { return }
        let origin = region.frame.position
        let width = max(1, region.frame.size.width.intValue)

        for localRow in region.start.line.intValue ... region.end.line.intValue {
            guard let columns = region.selectedColumns(inRow: localRow) else { continue }
            let absLine = origin.line + Extended(localRow)

            // Capture the full region row while it is on screen (for copy).
            var characters: [Character?] = []
            characters.reserveCapacity(width)
            var anyVisible = false
            for column in 0 ..< width {
                let char = buffer.character(
                    at: Position(column: origin.column + Extended(column), line: absLine)
                )
                if char != nil { anyVisible = true }
                characters.append(char)
            }
            if anyVisible {
                owner.captureVisibleRow(localRow, characters: characters)
            }

            // Snap boundaries so a wide character is never half-highlighted:
            // extend left off a continuation cell, and right across trailing
            // continuation cells.
            var lower = columns.lowerBound
            var upper = columns.upperBound
            while lower > 0, lower < characters.count, characters[lower] == "\u{0000}" {
                lower -= 1
            }
            while upper < width, upper < characters.count, characters[upper] == "\u{0000}" {
                upper += 1
            }

            for column in lower ..< upper {
                // `.selectionDisabled()` areas (line-number gutters) are never
                // part of the visual selection.
                if region.isMasked(column: column, row: localRow) { continue }
                buffer.highlightCell(
                    at: Position(column: origin.column + Extended(column), line: absLine),
                    background: TextSelectionStyle.background,
                    foreground: TextSelectionStyle.foreground
                )
            }
        }
    }
}
