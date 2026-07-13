import Foundation

// MARK: - TextAlignment

public enum TextAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

public extension EnvironmentValues {
    var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

public extension View {
    func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}

// MARK: - onSubmit

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

private struct SubmitActionKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var submitAction: (() -> Void)? {
        get { self[SubmitActionKey.self] }
        set { self[SubmitActionKey.self] = newValue }
    }
}

public extension View {
    func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        _ = triggers
        return environment(\.submitAction, action)
    }
}

extension EnvironmentValues {
    public var placeholderColor: Color {
        get { self[PlaceholderColorEnvironmentKey.self] }
        set { self[PlaceholderColorEnvironmentKey.self] = newValue }
    }
}

private struct PlaceholderColorEnvironmentKey: EnvironmentKey {
    static var defaultValue: Color { .brightBlack }
}

private final class StringBox: @unchecked Sendable {
    var value = ""
}

// MARK: - TextField

/// SwiftUI 风格单行输入：`Binding`、对齐、定宽下行内随光标滚动。
@MainActor
public struct TextField: View {
    private let placeholder: String
    private let text: Binding<String>
    private let legacyAction: ((String) -> Void)?

    @Environment(\.textFieldStyleKind) private var styleKind

    public init(_ title: String, text: Binding<String>) {
        self.placeholder = title
        self.text = text
        self.legacyAction = nil
    }

    public init(text: Binding<String>, prompt: String? = nil) {
        self.placeholder = prompt ?? ""
        self.text = text
        self.legacyAction = nil
    }

    /// 旧 API：回车提交。
    public init(placeholder: String? = nil, action: @escaping (String) -> Void) {
        self.placeholder = placeholder ?? ""
        self.legacyAction = action
        let box = StringBox()
        self.text = Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }

    public var body: some View {
        let core = TextFieldCore(
            placeholder: placeholder,
            text: text,
            legacyAction: legacyAction,
            secure: false
        )
        switch styleKind {
        case .roundedBorder:
            core.border(style: .rounded)
        case .squareBorder:
            core.border(style: .default)
        case .automatic, .plain:
            core
        }
    }
}

@MainActor
private struct TextFieldCore: View, PrimitiveView {
    let placeholder: String
    let text: Binding<String>
    let legacyAction: ((String) -> Void)?
    let secure: Bool

    @Environment(\.placeholderColor) private var placeholderColor: Color
    @Environment(\.multilineTextAlignment) private var alignment: TextAlignment
    @Environment(\.submitAction) private var submitAction: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled: Bool

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        let control = TextFieldControl(
            text: text,
            placeholder: placeholder,
            placeholderColor: placeholderColor,
            alignment: alignment,
            isEnabled: isEnabled,
            submitAction: submitAction,
            legacyAction: legacyAction
        )
        control.secure = secure
        node.control = control
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextFieldControl
        control.text = text
        control.placeholder = placeholder
        control.placeholderColor = placeholderColor
        control.alignment = alignment
        control.isEnabledFlag = isEnabled
        control.submitAction = submitAction
        control.legacyAction = legacyAction
        control.secure = secure
        control.syncFromBinding()
        control.layer.invalidate()
    }
}

@MainActor
final class TextFieldControl: Control {
    var text: Binding<String>
    var placeholder: String
    var placeholderColor: Color
    var alignment: TextAlignment
    var isEnabledFlag: Bool
    var submitAction: (() -> Void)?
    var legacyAction: ((String) -> Void)?
    /// SecureField：绘制为 `•`
    var secure = false

    /// 安全模式：刚输入的字符短暂明文显示（下一次输入或约 1s 后变 `•`）。
    private var revealedSecureIndex: Int? = nil
    private var revealWork: DispatchWorkItem?

    /// 光标在字符串中的 Character 偏移。
    private var cursorIndex: Int = 0
    /// 可见窗口左侧列偏移。
    private var scrollOffset: Int = 0
    private var cachedText: String = ""

    init(
        text: Binding<String>,
        placeholder: String,
        placeholderColor: Color,
        alignment: TextAlignment,
        isEnabled: Bool,
        submitAction: (() -> Void)?,
        legacyAction: ((String) -> Void)?
    ) {
        self.text = text
        self.placeholder = placeholder
        self.placeholderColor = placeholderColor
        self.alignment = alignment
        self.isEnabledFlag = isEnabled
        self.submitAction = submitAction
        self.legacyAction = legacyAction
        self.cachedText = text.wrappedValue
        self.cursorIndex = cachedText.count
    }

    func syncFromBinding() {
        let newText = text.wrappedValue
        if newText != cachedText {
            cachedText = newText
            cursorIndex = min(cursorIndex, cachedText.count)
            maskSecureImmediately()
            ensureCursorVisible()
        }
    }

    override var selectable: Bool { isEnabledFlag }

    override func size(proposedSize: Size) -> Size {
        // 有限宽度时占满提案宽（单行输入默认拉满）。
        if proposedSize.width != .infinity, proposedSize.width > 0 {
            return Size(width: proposedSize.width, height: 1)
        }
        let content = max(cachedText.width, placeholder.width, 10)
        return Size(width: Extended(content), height: 1)
    }

    override func layout(size: Size) {
        super.layout(size: size)
        ensureCursorVisible()
    }

    override func willRemoveFromParent() {
        cancelRevealTimer()
        super.willRemoveFromParent()
    }

    override func handleEvent(_ char: Character) {
        guard isEnabledFlag else { return }
        if char == "\n" {
            maskSecureImmediately()
            submitAction?()
            legacyAction?(cachedText)
            if legacyAction != nil {
                cachedText = ""
                cursorIndex = 0
                scrollOffset = 0
                text.wrappedValue = ""
                layer.invalidate()
            }
            return
        }
        if char == ASCII.DEL || char == "\u{7f}" {
            guard cursorIndex > 0 else { return }
            var chars = Array(cachedText)
            chars.remove(at: cursorIndex - 1)
            cachedText = String(chars)
            cursorIndex -= 1
            maskSecureImmediately()
            text.wrappedValue = cachedText
            ensureCursorVisible()
            layer.invalidate()
            return
        }
        var chars = Array(cachedText)
        chars.insert(char, at: cursorIndex)
        cachedText = String(chars)
        let insertedAt = cursorIndex
        cursorIndex += 1
        text.wrappedValue = cachedText
        if secure {
            revealSecureCharacter(at: insertedAt)
        }
        ensureCursorVisible()
        layer.invalidate()
    }

    override func handleKeyEvent(_ event: KeyEvent) {
        guard isEnabledFlag else { return }
        if event.keycode == VTKeyCode.left {
            if cursorIndex > 0 {
                cursorIndex -= 1
                maskSecureImmediately()
                ensureCursorVisible()
                layer.invalidate()
            }
            return
        }
        if event.keycode == VTKeyCode.right {
            if cursorIndex < cachedText.count {
                cursorIndex += 1
                maskSecureImmediately()
                ensureCursorVisible()
                layer.invalidate()
            }
            return
        }
        super.handleKeyEvent(event)
    }

    override func handleMouseEvent(_ event: MouseEvent) {
        guard isEnabledFlag else { return }
        if case .released(.left) = event.type {
            let local = event.position - absoluteFrame.position
            let col = max(0, local.column.intValue)
            cursorIndex = indexForVisibleColumn(col)
            maskSecureImmediately()
            ensureCursorVisible()
            layer.invalidate()
        } else {
            super.handleMouseEvent(event)
        }
    }

    override var cursorPosition: Position? {
        guard isFirstResponder, isEnabledFlag else { return nil }
        let cursorCol = columnOffset(upTo: cursorIndex)
        let visible = cursorCol - scrollOffset
        let width = max(1, layer.frame.size.width.intValue)
        guard visible >= 0, visible < width else { return nil }
        return Position(column: Extended(visible), line: 0)
    }

    override func draw(into buffer: inout ScreenBuffer) {
        let width = max(1, layer.frame.size.width.intValue)
        // 先清行再画字。不能用 `cell(at:) == nil` 填空格：VT 路径下 cell(at:) 恒为 nil，
        // 会把刚写入的正文整行盖成空格（表现为有光标/有内容却看不到字）。
        for x in 0 ..< width {
            buffer.setCell(Cell(char: " "), at: Position(column: Extended(x), line: 0))
        }

        let display: String
        let color: Color
        if cachedText.isEmpty {
            display = placeholder
            color = placeholderColor
        } else if secure {
            display = secureDisplayString()
            color = .default
        } else {
            display = cachedText
            color = .default
        }

        if cachedText.isEmpty {
            let totalWidth = display.width
            let startCol: Int
            switch alignment {
            case .leading: startCol = 0
            case .center: startCol = max(0, (width - totalWidth) / 2)
            case .trailing: startCol = max(0, width - totalWidth)
            }
            drawString(display, at: startCol, color: color, faint: true, into: &buffer, maxWidth: width)
        } else {
            ensureCursorVisible()
            let slice = visibleSlice(of: display, window: width)
            drawString(slice, at: 0, color: color, faint: false, into: &buffer, maxWidth: width)
        }
    }

    override func becomeFirstResponder() {
        super.becomeFirstResponder()
        layer.invalidate()
    }

    override func resignFirstResponder() {
        super.resignFirstResponder()
        maskSecureImmediately()
        layer.invalidate()
    }

    // MARK: - Secure reveal

    private func secureDisplayString() -> String {
        var result = ""
        for (i, ch) in cachedText.enumerated() {
            if revealedSecureIndex == i {
                result.append(ch)
            } else {
                result.append("•")
            }
        }
        return result
    }

    private func revealSecureCharacter(at index: Int) {
        cancelRevealTimer()
        revealedSecureIndex = index
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.revealedSecureIndex = nil
            self.layer.invalidate()
            self.layer.renderer?.application?.scheduleUpdate()
        }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func maskSecureImmediately() {
        cancelRevealTimer()
        if revealedSecureIndex != nil {
            revealedSecureIndex = nil
        }
    }

    private func cancelRevealTimer() {
        revealWork?.cancel()
        revealWork = nil
    }

    // MARK: - Scroll / columns

    /// 安全模式默认按 `•`（宽 1）；短暂明文的那一格用真实宽度。
    private func displayWidth(at index: Int, character: Character) -> Int {
        guard secure else { return character.width }
        if revealedSecureIndex == index {
            return character.width
        }
        return 1
    }

    private func columnOffset(upTo characterIndex: Int) -> Int {
        let chars = Array(cachedText)
        let end = min(characterIndex, chars.count)
        var total = 0
        for i in 0 ..< end {
            total += displayWidth(at: i, character: chars[i])
        }
        return total
    }

    private func ensureCursorVisible() {
        let width = max(1, layer.frame.size.width.intValue)
        let cursorCol = columnOffset(upTo: cursorIndex)
        if cursorCol < scrollOffset {
            scrollOffset = cursorCol
        } else if cursorCol >= scrollOffset + width {
            scrollOffset = cursorCol - width + 1
        }
        scrollOffset = max(0, scrollOffset)
    }

    private func visibleSlice(of string: String, window: Int) -> String {
        // `string` 已是最终显示串（含 • / 明文），按各字符真实显示宽切片。
        var col = 0
        var result = ""
        for ch in string {
            let w = ch.width
            let next = col + w
            if next <= scrollOffset {
                col = next
                continue
            }
            if col >= scrollOffset + window {
                break
            }
            result.append(ch)
            col = next
        }
        return result
    }

    private func indexForVisibleColumn(_ visibleColumn: Int) -> Int {
        let target = scrollOffset + visibleColumn
        var col = 0
        var index = 0
        for ch in cachedText {
            let w = displayWidth(at: index, character: ch)
            if col + w / 2 >= target { return index }
            col += w
            index += 1
            if col >= target { return index }
        }
        return cachedText.count
    }

    private func drawString(
        _ string: String,
        at startCol: Int,
        color: Color,
        faint: Bool,
        into buffer: inout ScreenBuffer,
        maxWidth: Int
    ) {
        var currentWidth = startCol
        for ch in string {
            let charWidth = ch.width
            if currentWidth >= maxWidth { break }
            if currentWidth + charWidth > maxWidth { break }
            var cell = Cell(char: ch, foregroundColor: color)
            cell.attributes.faint = faint
            buffer.setCell(cell, at: Position(column: Extended(currentWidth), line: 0))
            for w in 1 ..< charWidth {
                var cont = Cell(char: "\u{0000}", foregroundColor: color)
                cont.attributes.faint = faint
                buffer.setCell(cont, at: Position(column: Extended(currentWidth + w), line: 0))
            }
            currentWidth += charWidth
        }
    }
}
