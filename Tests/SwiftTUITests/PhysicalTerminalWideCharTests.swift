import Foundation
import Testing
@testable import SwiftTUI

/// Emulates the *physical* terminal: records the escape stream `present()`
/// emits and replays it onto a grid with real-terminal wide-char semantics
/// (a CJK glyph occupies two columns; partially overwriting a pair destroys
/// it). The logical back buffer can be perfectly restored while the physical
/// screen is torn — exactly the "popover closes but the half-covered Chinese
/// character never comes back" bug. Comparing emulated screen vs back buffer
/// after every frame catches that class of damage-paint bugs.
@Suite(.serialized)
@MainActor
struct PhysicalTerminalWideCharTests {

    @Test func popoverBorderOverCJKRestoresPhysicalScreenOnClose() async throws {
        let size = Size(width: 50, height: 16)
        struct Root: View {
            @State var show = false
            var body: some View {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Button("open") { show = true }
                        ForEach(0..<30, id: \.self) { i in
                            Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 24))
                        }
                    }
                }
                .popover(isPresented: $show) {
                    ScrollView {
                        Text(String(repeating: "面板内容行\n", count: 20))
                            .padding(.all, 1)
                    }
                    .frame(width: 30, height: 10)
                }
            }
        }

        let mock = RecordingTerminal(size: size)
        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size, terminal: mock)

        var screen = PhysicalScreenEmulator(width: size.widthInt, height: size.heightInt)
        screen.feed(await mock.drainOutput())
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "initial paint")

        try await clickButton("open", app)
        screen.feed(await mock.drainOutput())
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "popover open")

        try await app.testing_turn(input: .key(KeyEvent(
            character: "\u{1b}", keycode: VTKeyCode.escape, modifiers: [], type: .press
        )))
        try await app.testing_drainUntilIdle()
        #expect(app.window.popupPresenter?.isPresented == false, "popover should be closed")
        screen.feed(await mock.drainOutput())
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "after close")
    }

    @Test func sheetOverCJKRestoresPhysicalScreenOnClose() async throws {
        let size = Size(width: 44, height: 14)
        struct Root: View {
            @State var show = false
            var body: some View {
                VStack(spacing: 0) {
                    Button("open") { show = true }
                    ForEach(0..<12, id: \.self) { i in
                        Text((i % 2 == 0 ? "" : " ") + String(repeating: "中", count: 21))
                    }
                }
                .sheet(isPresented: $show) {
                    Text("面板内容")
                }
            }
        }

        let mock = RecordingTerminal(size: size)
        let app = Application(rootView: Root())
        try await app.testing_prepareVT(size: size, terminal: mock)

        var screen = PhysicalScreenEmulator(width: size.widthInt, height: size.heightInt)
        screen.feed(await mock.drainOutput())

        try await clickButton("open", app)
        screen.feed(await mock.drainOutput())
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "sheet open")

        try await app.testing_turn(input: .key(KeyEvent(
            character: "\u{1b}", keycode: VTKeyCode.escape, modifiers: [], type: .press
        )))
        try await app.testing_drainUntilIdle()
        #expect(app.window.popupPresenter?.isPresented == false, "sheet should be closed")
        screen.feed(await mock.drainOutput())
        try expectPhysicalMatchesBackBuffer(app, screen: screen, size: size, "after sheet close")
    }

    // MARK: - Helpers

    private func expectPhysicalMatchesBackBuffer(
        _ app: Application,
        screen: PhysicalScreenEmulator,
        size: Size,
        _ context: @autoclosure () -> String
    ) throws {
        var mismatches: [String] = []
        for line in 0 ..< size.heightInt {
            for column in 0 ..< size.widthInt {
                let logical = app.testing_vtCharacter(
                    at: Position(column: Extended(column), line: Extended(line))
                ) ?? " "
                let physical = screen.character(atColumn: column + 1, row: line + 1)
                if logical != physical {
                    mismatches.append(
                        "(\(column),\(line)) logical \(String(reflecting: logical)) physical \(String(reflecting: physical))"
                    )
                }
            }
        }
        #expect(
            mismatches.isEmpty,
            "\(context()): physical screen diverged in \(mismatches.count) cells: \(mismatches.prefix(12).joined(separator: ", "))"
        )
    }

    private func clickButton(_ label: String, _ app: Application) async throws {
        let button = try #require(findButton(label, in: app.testing_rootElement))
        let frame = button.absoluteFrame
        let pos = Position(
            column: frame.position.column + max(Extended(0), frame.size.width / 2),
            line: frame.position.line + max(Extended(0), frame.size.height / 2)
        )
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .pressed(.left))))
        try await app.testing_turn(input: .mouse(MouseEvent(position: pos, type: .released(.left))))
        try await app.testing_drainUntilIdle()
    }

    private func findButton(_ label: String, in root: Element?) -> Element? {
        guard let root else { return nil }
        if String(describing: type(of: root)).contains("Button"), buttonText(root) == label {
            return root
        }
        for child in root.children {
            if let found = findButton(label, in: child) { return found }
        }
        return nil
    }

    private func buttonText(_ control: Element) -> String? {
        if let text = Mirror(reflecting: control).children.first(where: { $0.label == "text" })?.value as? String {
            return text
        }
        for child in control.children {
            if let t = buttonText(child) { return t }
        }
        return nil
    }
}

// MARK: - Recording terminal

/// Minimal `VTTerminal` that records every write; no real IO, no input.
actor RecordingTerminal: VTTerminal {
    nonisolated let size: Size
    nonisolated let input: VTEventStream

    private var output = ""

    init(size: Size) {
        self.size = size
        self.input = VTEventStream(AsyncThrowingStream { _ in })
    }

    func write(_ string: String) {
        output += string
    }

    func drainOutput() -> String {
        defer { output = "" }
        return output
    }
}

// MARK: - Physical screen emulator

/// Replays a VT escape stream with real-terminal wide-char semantics:
/// - a width-2 glyph occupies its column and the next (continuation `\u{0000}`);
/// - overwriting *either half* of a wide pair blanks the other half;
/// - the cursor advances by the glyph's physical width.
/// Only the sequences `VTRenderer.paint` emits are interpreted; other CSI /
/// mode toggles are skipped.
struct PhysicalScreenEmulator {
    let width: Int
    let height: Int
    private var grid: [Character]
    private var row = 1
    private var col = 1

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.grid = Array(repeating: " ", count: width * height)
    }

    func character(atColumn column: Int, row: Int) -> Character {
        guard column >= 1, column <= width, row >= 1, row <= height else { return " " }
        return grid[(row - 1) * width + (column - 1)]
    }

    mutating func feed(_ stream: String) {
        var iterator = Substring(stream).makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return iterator.next()
        }

        while let ch = next() {
            if ch == "\u{1B}" {
                guard let kind = next() else { return }
                if kind == "[" {
                    // CSI: parameters until a final byte (letter or ~).
                    var params = ""
                    var final: Character? = nil
                    while let c = next() {
                        if c.isLetter || c == "~" {
                            final = c
                            break
                        }
                        params.append(c)
                    }
                    if let final {
                        applyCSI(params: params, final: final)
                    }
                } else if kind == "]" {
                    // OSC: consume until BEL or ST.
                    while let c = next() {
                        if c == "\u{07}" { break }
                        if c == "\u{1B}", let n = next() {
                            if n == "\\" { break }
                            pending = n
                        }
                    }
                }
                continue
            }
            if ch == "\r" { col = 1; continue }
            if ch == "\n" { row = min(height, row + 1); continue }
            putChar(ch)
        }
    }

    private mutating func applyCSI(params: String, final: Character) {
        // Private modes (?...h/l), SGR (m), erase (J/K) etc. do not move cells.
        if params.hasPrefix("?") { return }
        let numbers = params.split(separator: ";").map { Int($0) ?? 1 }
        let n = numbers.first ?? 1
        switch final {
        case "H", "f":
            row = max(1, min(height, numbers.count >= 1 ? numbers[0] : 1))
            col = max(1, min(width, numbers.count >= 2 ? numbers[1] : 1))
        case "A": row = max(1, row - n)
        case "B": row = min(height, row + n)
        case "C": col = min(width, col + n)
        case "D": col = max(1, col - n)
        case "E": row = min(height, row + n); col = 1
        case "F": row = max(1, row - n); col = 1
        case "G": col = max(1, min(width, n))
        default: break
        }
    }

    private mutating func putChar(_ ch: Character) {
        let w = ch.width
        guard w > 0 else { return }
        guard row >= 1, row <= height else { return }
        if col > width { return }
        // A wide glyph that would overflow the row is dropped (paint never
        // relies on autowrap inside a damage span).
        if col + w - 1 > width { return }

        for offset in 0 ..< w {
            destroyPair(atColumn: col + offset)
        }
        set(col, ch)
        if w == 2 {
            set(col + 1, "\u{0000}")
        }
        col += w
    }

    /// Overwriting either half of an existing wide pair blanks the other half
    /// (Windows Terminal / xterm behavior).
    private mutating func destroyPair(atColumn column: Int) {
        guard column >= 1, column <= width else { return }
        let ch = cell(column)
        if ch == "\u{0000}" {
            if column - 1 >= 1 { set(column - 1, " ") }
            set(column, " ")
        } else if ch.width == 2, column + 1 <= width, cell(column + 1) == "\u{0000}" {
            set(column + 1, " ")
        }
    }

    private func cell(_ column: Int) -> Character {
        grid[(row - 1) * width + (column - 1)]
    }

    private mutating func set(_ column: Int, _ ch: Character) {
        guard column >= 1, column <= width else { return }
        grid[(row - 1) * width + (column - 1)] = ch
    }
}
