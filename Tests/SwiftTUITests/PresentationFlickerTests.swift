import Testing
@testable import SwiftTUI

/// Popover/menu must not dirty the full window (navigation bar flicker) and
/// scrolling must not erase the navigation toolbar.
@Suite(.serialized)
@MainActor
struct PresentationFlickerTests {

    @Test func popoverOpenDirtyRectStaysLocal() async throws {
        let size = Size(width: 50, height: 20)
        struct Root: View {
            @State var show = false
            var body: some View {
                VStack(spacing: 0) {
                    Button("open") { show = true }
                    ForEach(0..<8, id: \.self) { i in
                        Text("row-\(i)")
                    }
                }
                .popover(isPresented: $show) {
                    Text("panel-body")
                        .padding(.all, 1)
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)

        try await pfClickButton("open", on: app)
        try await app.testing_drainUntilIdle()

        let dirty = try #require(app.testing_lastPaintRect)
        let windowArea = size.width.intValue * size.height.intValue
        let dirtyArea = dirty.size.width.intValue * dirty.size.height.intValue
        #expect(
            dirtyArea < windowArea,
            "popover open should not repaint the full window (dirty=\(dirtyArea) window=\(windowArea))"
        )
        #expect(dirty.size.height.intValue <= 6, "popover dirty height should stay small")
    }

    @Test func scrollKeepsNavigationToolbar() async throws {
        let size = Size(width: 50, height: 16)
        struct Root: View {
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<40, id: \.self) { i in
                                Text("line-\(i)")
                            }
                        }
                    }
                    .navigationTitle("Title")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Edit") {}
                        }
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)
        #expect(pfFindButton("Edit", in: app.testing_rootElement) != nil)

        // Wheel down several times — must not erase the toolbar row.
        for _ in 0 ..< 6 {
            try await app.testing_turn(input: .mouse(MouseEvent(
                position: Position(column: 10, line: 10),
                type: .scroll(deltaX: 0, deltaY: 3)
            )))
        }
        try await app.testing_drainUntilIdle()

        #expect(pfFindButton("Edit", in: app.testing_rootElement) != nil, "toolbar action must survive scroll")
        #expect(pfFindButton("Title", in: app.testing_rootElement) != nil, "navigation title must survive scroll")
    }

    @Test func scrollUnderOpenPopoverKeepsNavigationToolbar() async throws {
        let size = Size(width: 50, height: 18)
        struct Root: View {
            @State var show = false
            var body: some View {
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Button("open") { show = true }
                            ForEach(0..<30, id: \.self) { i in
                                Text("line-\(i)")
                            }
                        }
                    }
                    .navigationTitle("Title")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Edit") {}
                        }
                    }
                    .popover(isPresented: $show) {
                        ScrollView {
                            Text("panel")
                                .padding(.all, 1)
                        }
                        .frame(width: 20, height: 6)
                    }
                }
            }
        }

        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size)

        try await pfClickButton("open", on: app)
        try await app.testing_drainUntilIdle()
        #expect(app.window.popupPresenter?.isPresented == true)

        for _ in 0 ..< 4 {
            try await app.testing_turn(input: .mouse(MouseEvent(
                position: Position(column: 10, line: 12),
                type: .scroll(deltaX: 0, deltaY: 2)
            )))
        }
        try await app.testing_drainUntilIdle()

        #expect(pfFindButton("Edit", in: app.testing_rootElement) != nil, "toolbar must stay while popover is open")
        #expect(pfFindButton("Title", in: app.testing_rootElement) != nil)
    }
}

// MARK: - Helpers

@MainActor
private func pfTextLabel(in control: Element) -> String? {
    if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
        return text
    }
    for child in control.children {
        if let text = pfTextLabel(in: child) { return text }
    }
    return nil
}

@MainActor
private func pfFindButton(_ label: String, in root: Element?) -> Element? {
    guard let root else { return nil }
    if String(describing: type(of: root)).contains("Button"), pfTextLabel(in: root) == label {
        return root
    }
    for child in root.children {
        if let found = pfFindButton(label, in: child) { return found }
    }
    return nil
}

@MainActor
private func pfCenter(of control: Element) -> Position {
    let frame = control.absoluteFrame
    return Position(
        column: frame.position.column + max(Extended(0), frame.size.width / 2),
        line: frame.position.line + max(Extended(0), frame.size.height / 2)
    )
}

@MainActor
private func pfClickButton(_ label: String, on app: Application) async throws {
    let button = try #require(pfFindButton(label, in: app.testing_rootElement))
    let pos = pfCenter(of: button)
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
    try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
}
