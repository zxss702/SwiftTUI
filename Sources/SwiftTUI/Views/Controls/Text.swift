import Foundation

@MainActor public struct Text: View, PrimitiveView {
    private var text: String?

    private var _attributedText: Any?

    @available(macOS 12, *)
    private var attributedText: AttributedString? { _attributedText as? AttributedString }

    @Environment(\.foregroundColor) private var foregroundColor: Color
    @Environment(\.bold) private var bold: Bool
    @Environment(\.italic) private var italic: Bool
    @Environment(\.underline) private var underline: Bool
    @Environment(\.strikethrough) private var strikethrough: Bool
    @Environment(\.lineLimit) private var lineLimit: Int?
    @Environment(\.truncationMode) private var truncationMode: TruncationMode

    public init(_ text: String) {
        self.text = text
    }

    @available(macOS 12, *)
    public init(_ attributedText: AttributedString) {
        self._attributedText = attributedText
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        let resolved = resolvedContent
        node.element = TextElement(
            text: resolved.string,
            styledChars: resolved.styles,
            foregroundColor: foregroundColor,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            lineLimit: lineLimit,
            truncationMode: truncationMode
        )
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.element as! TextElement
        let previousText = control.text
        let previousLineLimit = control.lineLimit
        let previousTruncation = control.truncationMode
        let resolved = resolvedContent
        control.text = resolved.string
        control.styledChars = resolved.styles
        control.foregroundColor = foregroundColor
        control.bold = bold
        control.italic = italic
        control.underline = underline
        control.strikethrough = strikethrough
        control.lineLimit = lineLimit
        control.truncationMode = truncationMode
        // Measurement-affecting changes must always relayout. Probing with the
        // *current* frame width is wrong: a longer string measured in a stale
        // narrow frame can report the same width (clipped) and skip layout,
        // leaving Picker/Menu labels stuck until the window is resized.
        if previousText != control.text
            || previousLineLimit != lineLimit
            || previousTruncation != truncationMode
        {
            control.invalidateSizeCacheUpward()
            node.root.application?.requestLayout()
        }
        control.layer.invalidate()
    }

    private var resolvedContent: (string: String, styles: [StyledChar]?) {
        if #available(macOS 12, *), let attributedText {
            return AttributedTextStyle.flatten(attributedText)
        }
        return (text ?? "", nil)
    }

    private class TextElement: Element {
        var text: String
        var styledChars: [StyledChar]?
        var foregroundColor: Color
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var strikethrough: Bool
        var lineLimit: Int?
        var truncationMode: Text.TruncationMode

        /// 当前用于绘制 / 命中测试的换行结果（宽度与 `layer.frame` 一致）。
        private var cachedLines: [TextLayout.LaidOutLine] = []

        // MARK: 换行缓存
        //
        // `size()` / `layout()` 会以多个宽度（∞ / 0 / 有限）被反复调用（VStack 排序的
        // flexibility、ScrollView refine、LazyVStack 多趟布局）。这里按宽度缓存换行结果，
        // 只要 (文字, lineLimit, truncationMode) 不变就直接复用，避免重复整段换行。
        // 纯 Foundation + Dictionary，MainActor 隔离，跨平台安全。
        private struct LineCacheSignature: Equatable {
            var text: String
            var lineLimit: Int?
            var truncationMode: Text.TruncationMode
        }
        private var lineCacheSignature: LineCacheSignature?
        private var lineCache: [Int: [TextLayout.LaidOutLine]] = [:]
        private var cachedIntrinsicWidth: Int?

        private func ensureCacheFresh() {
            let signature = LineCacheSignature(
                text: text,
                lineLimit: lineLimit,
                truncationMode: truncationMode
            )
            if lineCacheSignature != signature {
                lineCacheSignature = signature
                lineCache.removeAll(keepingCapacity: true)
                cachedIntrinsicWidth = nil
            }
        }

        private func laidOutLines(width: Int) -> [TextLayout.LaidOutLine] {
            ensureCacheFresh()
            if let cached = lineCache[width] {
                return cached
            }
            let lines = TextLayout.lines(
                for: text,
                width: width,
                lineLimit: lineLimit,
                truncationMode: truncationMode
            )
            lineCache[width] = lines
            return lines
        }

        private func intrinsicWidth() -> Int {
            ensureCacheFresh()
            if let cachedIntrinsicWidth { return cachedIntrinsicWidth }
            let width = max(text.width, 1)
            cachedIntrinsicWidth = width
            return width
        }

        init(
            text: String,
            styledChars: [StyledChar]?,
            foregroundColor: Color,
            bold: Bool,
            italic: Bool,
            underline: Bool,
            strikethrough: Bool,
            lineLimit: Int?,
            truncationMode: Text.TruncationMode
        ) {
            self.text = text
            self.styledChars = styledChars
            self.foregroundColor = foregroundColor
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
            self.lineLimit = lineLimit
            self.truncationMode = truncationMode
        }

        override func size(proposedSize: Size) -> Size {
            let width = resolvedWidth(proposedSize: proposedSize)
            let lines = laidOutLines(width: width)
            cachedLines = lines
            let contentWidth = lines.map(\.visualWidth).max() ?? 0
            let height = max(lines.count, 1)
            return Size(width: Extended(contentWidth), height: Extended(height))
        }

        override func layout(size: Size) {
            super.layout(size: size)
            let width = max(size.width.intValue, 1)
            cachedLines = laidOutLines(width: width)
        }

        /// Claim clicks only when attributed text contains link URLs.
        override var claimsPointerCapture: Bool {
            styledChars?.contains(where: { $0.linkURL != nil }) == true
        }

        override func pointerGesture(_ event: PointerGestureEvent) -> Bool {
            guard claimsPointerCapture, event.button == .left else { return false }
            let local = event.position - absoluteFrame.position
            guard let urlString = linkURL(
                atColumn: local.column.intValue,
                line: local.line.intValue
            ) else {
                return false
            }
            if event.phase == .ended {
                if let url = URL(string: urlString) {
                    OpenURL.open(url)
                } else {
                    OpenURL.open(urlString)
                }
            }
            return event.phase == .began || event.phase == .ended || event.phase == .moved
        }

        private func linkURL(atColumn column: Int, line: Int) -> String? {
            guard line >= 0, line < cachedLines.count, column >= 0 else { return nil }
            var currentWidth = 0
            for unit in cachedLines[line].units {
                let charWidth = max(unit.char.width, unit.char == "\t" ? 1 : 0)
                if charWidth <= 0 { continue }
                if column >= currentWidth && column < currentWidth + charWidth {
                    guard let sourceIndex = unit.sourceIndex,
                          let styledChars,
                          sourceIndex >= 0,
                          sourceIndex < styledChars.count
                    else {
                        return nil
                    }
                    return styledChars[sourceIndex].linkURL
                }
                currentWidth += charWidth
            }
            return nil
        }

        override func draw(into buffer: inout ScreenBuffer) {
            let maxWidth = layer.frame.size.width.intValue
            let maxHeight = layer.frame.size.height.intValue
            let envAttributes = CellAttributes(
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough
            )

            for lineIndex in 0 ..< maxHeight {
                var currentWidth = 0
                if lineIndex < cachedLines.count {
                    let line = cachedLines[lineIndex]
                    for unit in line.units {
                        let char = unit.char
                        let style = resolvedStyle(for: unit.sourceIndex, envAttributes: envAttributes)
                        let charWidth = char.width
                        if charWidth <= 0 {
                            if char == "\t", currentWidth < maxWidth {
                                buffer.setCell(
                                    Cell(
                                        char: " ",
                                        foregroundColor: style.foreground,
                                        backgroundColor: style.background,
                                        attributes: style.attributes
                                    ),
                                    at: Position(column: Extended(currentWidth), line: Extended(lineIndex))
                                )
                                currentWidth += 1
                            }
                            continue
                        }
                        if currentWidth + charWidth > maxWidth { break }
                        buffer.setCell(
                            Cell(
                                char: char,
                                foregroundColor: style.foreground,
                                backgroundColor: style.background,
                                attributes: style.attributes
                            ),
                            at: Position(column: Extended(currentWidth), line: Extended(lineIndex))
                        )
                        if charWidth > 1 {
                            for w in 1 ..< charWidth {
                                buffer.setCell(
                                    Cell(
                                        char: "\u{0000}",
                                        foregroundColor: style.foreground,
                                        backgroundColor: style.background,
                                        attributes: style.attributes
                                    ),
                                    at: Position(column: Extended(currentWidth + w), line: Extended(lineIndex))
                                )
                            }
                        }
                        currentWidth += charWidth
                    }
                }
                for w in currentWidth ..< maxWidth {
                    buffer.setCell(
                        Cell(char: " "),
                        at: Position(column: Extended(w), line: Extended(lineIndex))
                    )
                }
            }
        }

        private func resolvedStyle(
            for sourceIndex: Int?,
            envAttributes: CellAttributes
        ) -> (foreground: Color, background: Color?, attributes: CellAttributes) {
            guard let sourceIndex,
                  let styledChars,
                  sourceIndex >= 0,
                  sourceIndex < styledChars.count
            else {
                return (foregroundColor, nil, envAttributes)
            }
            let styled = styledChars[sourceIndex]
            return (
                styled.foreground ?? foregroundColor,
                styled.background,
                CellAttributes(
                    bold: styled.bold ?? bold,
                    italic: styled.italic ?? italic,
                    underline: styled.underline ?? underline,
                    strikethrough: styled.strikethrough ?? strikethrough,
                    inverted: styled.inverted ?? false
                )
            )
        }

        private func resolvedWidth(proposedSize: Size) -> Int {
            if proposedSize.width == .infinity {
                // 无宽度约束时按单行完整内容测量；lineLimit 只限制高度行数
                return intrinsicWidth()
            }
            return max(proposedSize.width.intValue, 1)
        }
    }
}

// MARK: - Attributed style flattening

struct StyledChar: Equatable {
    var foreground: Color?
    var background: Color?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strikethrough: Bool?
    var inverted: Bool?
    var linkURL: String?

    init(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        inverted: Bool? = nil,
        linkURL: String? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverted = inverted
        self.linkURL = linkURL
    }
}

@available(macOS 12, *)
enum AttributedTextStyle {
    static func flatten(_ attributed: AttributedString) -> (string: String, styles: [StyledChar]?) {
        let string = String(attributed.characters)
        guard !string.isEmpty else { return (string, []) }

        var styles: [StyledChar] = []
        styles.reserveCapacity(attributed.characters.count)

        for run in attributed.runs {
            typealias Attr = AttributeScopes.SwiftTUIAttributes
            let attrs = run.attributes
            let style = StyledChar(
                foreground: attrs[Attr.ForegroundColorAttribute.self],
                background: attrs[Attr.BackgroundColorAttribute.self],
                bold: attrs[Attr.BoldAttribute.self],
                italic: attrs[Attr.ItalicAttribute.self],
                underline: attrs[Attr.UnderlineAttribute.self],
                strikethrough: attrs[Attr.StrikethroughAttribute.self],
                inverted: attrs[Attr.InvertedAttribute.self],
                linkURL: attrs[Attr.LinkURLAttribute.self]
            )
            let count = attributed[run.range].characters.count
            for _ in 0 ..< count {
                styles.append(style)
            }
        }

        return (string, styles)
    }
}

// MARK: - TextLayout

public enum TextLayout {
    static let ellipsis = "…"

    /// Public helper for siblings that need to match soft-wrap row heights.
    public static func wrappedLineCount(for text: String, width: Int) -> Int {
        max(1, wrap(text, width: max(width, 1)).count)
    }

    struct LaidOutLine: Equatable {
        struct Unit: Equatable {
            let char: Character
            /// Absolute Character index into the original string; `nil` for synthetic glyphs (ellipsis).
            let sourceIndex: Int?
        }

        var units: [Unit]

        var string: String { String(units.map(\.char)) }

        var visualWidth: Int {
            units.reduce(0) { partial, unit in
                let w = unit.char.width
                if w <= 0 { return unit.char == "\t" ? partial + 1 : partial }
                return partial + w
            }
        }
    }

    static func lines(
        for text: String,
        width: Int,
        lineLimit: Int?,
        truncationMode: Text.TruncationMode
    ) -> [LaidOutLine] {
        let width = max(width, 1)
        let sourceUnits: [LaidOutLine.Unit] = text.enumerated().map {
            LaidOutLine.Unit(char: $0.element, sourceIndex: $0.offset)
        }
        let wrapped = wrap(sourceUnits, width: width)

        guard let limit = lineLimit else {
            return wrapped.isEmpty ? [LaidOutLine(units: [])] : wrapped
        }

        if limit <= 0 {
            return []
        }

        if wrapped.count <= limit {
            return wrapped
        }

        switch truncationMode {
        case .tail:
            return truncateTail(units: sourceUnits, width: width, maxLines: limit)
        case .head:
            return truncateHead(units: sourceUnits, width: width, maxLines: limit)
        case .middle:
            return truncateMiddle(units: sourceUnits, width: width, maxLines: limit)
        }
    }

    /// 按可视宽度软换行（支持显式 `\n`）。
    static func wrap(_ text: String, width: Int) -> [String] {
        let units: [LaidOutLine.Unit] = text.enumerated().map {
            LaidOutLine.Unit(char: $0.element, sourceIndex: $0.offset)
        }
        return wrap(units, width: width).map(\.string)
    }

    static func wrap(_ units: [LaidOutLine.Unit], width: Int) -> [LaidOutLine] {
        guard !units.isEmpty else { return [LaidOutLine(units: [])] }

        var lines: [LaidOutLine] = []
        var lineStart = 0
        var lineWidth = 0
        var lastBreakOpportunity: Int?

        func unitWidth(_ unit: LaidOutLine.Unit) -> Int {
            let w = unit.char.width
            if w <= 0 { return unit.char == "\t" ? 1 : 0 }
            return w
        }

        func flushLine(upTo end: Int) {
            lines.append(LaidOutLine(units: Array(units[lineStart ..< end])))
            lineStart = end
            lineWidth = 0
            lastBreakOpportunity = nil
        }

        func skipLeadingSpaces(_ index: inout Int) {
            while index < units.count, units[index].char == " " {
                index += 1
                lineStart = index
            }
        }

        func recomputeLineWidth(upTo end: Int) {
            lineWidth = units[lineStart ..< end].reduce(0) { $0 + unitWidth($1) }
        }

        var index = 0
        while index < units.count {
            let unit = units[index]

            if LineBreakEngine.isMandatoryBreak(unit.char) || unit.char == "\n" {
                flushLine(upTo: index)
                index += 1
                lineStart = index
                continue
            }

            let charWidth = unitWidth(unit)
            if lineWidth + charWidth > width, index > lineStart {
                let breakAt = LineBreakEngine.chooseBreakPoint(
                    units: units,
                    lineStart: lineStart,
                    exclusiveEnd: index,
                    lastOpportunity: lastBreakOpportunity
                )
                flushLine(upTo: breakAt)
                skipLeadingSpaces(&index)
                recomputeLineWidth(upTo: index)
                continue
            }

            lineWidth += charWidth
            if index + 1 < units.count {
                let next = units[index + 1].char
                if LineBreakEngine.canBreak(after: unit.char, before: next) {
                    lastBreakOpportunity = index
                }
            }
            index += 1
        }

        if lineStart < units.count {
            lines.append(LaidOutLine(units: Array(units[lineStart...])))
        } else if !units.isEmpty {
            lines.append(LaidOutLine(units: []))
        }
        return lines.isEmpty ? [LaidOutLine(units: [])] : lines
    }

    private static func truncateTail(
        units: [LaidOutLine.Unit],
        width: Int,
        maxLines: Int
    ) -> [LaidOutLine] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let prefix = prefixFitting(units, maxWidth: budget)
        let combined = prefix + ellipsisUnits()
        return capped(wrap(combined, width: width), maxLines: maxLines)
    }

    private static func truncateHead(
        units: [LaidOutLine.Unit],
        width: Int,
        maxLines: Int
    ) -> [LaidOutLine] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let suffix = suffixFitting(units, maxWidth: budget)
        let combined = ellipsisUnits() + suffix
        return capped(wrap(combined, width: width), maxLines: maxLines)
    }

    private static func truncateMiddle(
        units: [LaidOutLine.Unit],
        width: Int,
        maxLines: Int
    ) -> [LaidOutLine] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let left = budget / 2
        let right = budget - left
        let prefix = prefixFitting(units, maxWidth: left)
        let suffix = suffixFitting(units, maxWidth: right)
        let combined = prefix + ellipsisUnits() + suffix
        return capped(wrap(combined, width: width), maxLines: maxLines)
    }

    private static func ellipsisUnits() -> [LaidOutLine.Unit] {
        TextLayout.ellipsis.map { LaidOutLine.Unit(char: $0, sourceIndex: nil) }
    }

    private static func capped(_ lines: [LaidOutLine], maxLines: Int) -> [LaidOutLine] {
        Array(lines.prefix(maxLines))
    }

    private static func prefixFitting(_ units: [LaidOutLine.Unit], maxWidth: Int) -> [LaidOutLine.Unit] {
        var result: [LaidOutLine.Unit] = []
        var width = 0
        for unit in units {
            if unit.char == "\n" {
                if width + 1 > maxWidth { break }
                result.append(unit)
                width += 1
                continue
            }
            let charWidth = unit.char.width
            if width + charWidth > maxWidth { break }
            result.append(unit)
            width += charWidth
        }
        return result
    }

    private static func suffixFitting(_ units: [LaidOutLine.Unit], maxWidth: Int) -> [LaidOutLine.Unit] {
        var result: [LaidOutLine.Unit] = []
        var width = 0
        for unit in units.reversed() {
            if unit.char == "\n" {
                if width + 1 > maxWidth { break }
                result.insert(unit, at: 0)
                width += 1
                continue
            }
            let charWidth = unit.char.width
            if width + charWidth > maxWidth { break }
            result.insert(unit, at: 0)
            width += charWidth
        }
        return result
    }
}
