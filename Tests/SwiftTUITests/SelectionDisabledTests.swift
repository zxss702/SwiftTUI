import Foundation
import Testing
@testable import SwiftTUI

/// `.selectionDisabled()` inside a `.selectable()` region: masked areas
/// (line-number gutters) are never highlighted and never copied.
/// Mirrors Logorythia `CodeDiffView` (gutter + code columns).
@Suite(.serialized)
@MainActor
struct SelectionDisabledTests {

    private func drag(_ app: Application, from: Position, to: Position) async throws {
        try await app.testing_turn(input: .mouse(MouseEvent(position: from, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .move)))
        try await app.testing_turn(input: .mouse(MouseEvent(position: to, type: .released(.left))))
    }

    /// Two rows shaped like a diff: `[gutter][code]`, gutter marked
    /// `.selectionDisabled()`. Dragging across both rows copies only the code.
    @Test func copiedTextSkipsSelectionDisabledGutter() async throws {
        struct Root: View {
            var body: some View {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("11 ").selectionDisabled()
                        Text("code-a")
                    }
                    HStack(spacing: 0) {
                        Text("22 ").selectionDisabled()
                        Text("code-b")
                    }
                }
                .selectable()
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 30, height: 6))
        let selectable = try #require(
            findMaskTestElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position

        // Select both full rows, starting inside the gutter.
        try await drag(
            app,
            from: origin,
            to: origin + Position(column: 8, line: 1)
        )
        #expect(selectable.hasSelection)

        let text = try #require(selectable.selectedText())
        #expect(text == "code-a\ncode-b", "gutter must not be copied, got \(text.debugDescription)")
    }

    /// The visual highlight pass must leave masked cells unstyled.
    @Test func highlightSkipsSelectionDisabledGutter() async throws {
        struct Root: View {
            var body: some View {
                HStack(spacing: 0) {
                    Text("42 ").selectionDisabled()
                    Text("payload")
                }
                .selectable()
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 30, height: 4))
        let selectable = try #require(
            findMaskTestElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 9, line: 0))
        #expect(selectable.hasSelection)

        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)
        app.window.selectionCoordinator.applyHighlight(into: &buffer)

        // Gutter cell (column 0) is masked; code cell (column 3+) highlighted.
        let gutterCell = try #require(buffer.cell(at: origin))
        #expect(
            gutterCell.backgroundColor != TextSelectionStyle.background,
            "gutter cell must not be highlighted"
        )
        let codeCell = try #require(buffer.cell(at: origin + Position(column: 3, line: 0)))
        #expect(
            codeCell.backgroundColor == TextSelectionStyle.background,
            "code cell must be highlighted"
        )
    }

    /// Soft-wrapped row: the gutter is one line tall but the row spans two
    /// lines. The masked band must cover the gutter columns on *all* the
    /// row's lines, so the continuation line has no selectable stub sticking
    /// out on the left (CodeDiffView wrapped diff lines).
    @Test func maskCoversGutterColumnsOnWrappedRowLines() async throws {
        struct Root: View {
            var body: some View {
                HStack(alignment: .top, spacing: 0) {
                    Text("42 ").selectionDisabled()
                    Text("line-a\nline-b")
                }
                .selectable()
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 30, height: 4))
        let selectable = try #require(
            findMaskTestElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position

        // Select both lines fully, starting at the gutter of line 0.
        try await drag(app, from: origin, to: origin + Position(column: 8, line: 1))
        #expect(selectable.hasSelection)

        let text = try #require(selectable.selectedText())
        #expect(
            text == "line-a\nline-b",
            "wrapped line's gutter columns must not be copied, got \(text.debugDescription)"
        )

        var buffer = ScreenBuffer(rect: Rect(position: .zero, size: app.window.layer.frame.size))
        app.window.layer.draw(into: &buffer)
        app.window.selectionCoordinator.applyHighlight(into: &buffer)

        for line in 0 ... 1 {
            let gutterCell = try #require(buffer.cell(at: origin + Position(column: 0, line: Extended(line))))
            #expect(
                gutterCell.backgroundColor != TextSelectionStyle.background,
                "line \(line): gutter column must not be highlighted"
            )
        }
        let codeCell = try #require(buffer.cell(at: origin + Position(column: 3, line: 1)))
        #expect(
            codeCell.backgroundColor == TextSelectionStyle.background,
            "second line content must be highlighted"
        )
    }

    /// `selectionDisabled(false)` is a no-op: the area stays selectable.
    @Test func selectionDisabledFalseKeepsAreaSelectable() async throws {
        struct Root: View {
            var body: some View {
                HStack(spacing: 0) {
                    Text("42 ").selectionDisabled(false)
                    Text("payload")
                }
                .selectable()
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepare(size: Size(width: 30, height: 4))
        let selectable = try #require(
            findMaskTestElement(in: app.testing_rootElement, typeContains: "SelectableElement") as? SelectableElement
        )
        let origin = selectable.absoluteFrame.position

        try await drag(app, from: origin, to: origin + Position(column: 9, line: 0))
        let text = try #require(selectable.selectedText())
        #expect(text == "42 payload", "disabled=false must keep the gutter, got \(text.debugDescription)")
    }
}

@MainActor
private func findMaskTestElement(in control: Element?, typeContains name: String) -> Element? {
    guard let control else { return nil }
    if String(describing: type(of: control)).contains(name) { return control }
    for child in control.children {
        if let found = findMaskTestElement(in: child, typeContains: name) { return found }
    }
    return nil
}
