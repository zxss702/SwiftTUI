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
        // Only reflow when measured size would change; pure repaints skip full-tree layout.
        if previousText != control.text
            || previousLineLimit != lineLimit
            || previousTruncation != truncationMode
        {
            let width = control.layer.frame.size.width
            if width > 0 {
                let measured = control.size(proposedSize: Size(width: width, height: .infinity))
                if measured.height != control.layer.frame.size.height
                    || measured.width != control.layer.frame.size.width
                {
                    node.root.application?.requestLayout()
                }
            } else {
                node.root.application?.requestLayout()
            }
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

        private var cachedLines: [TextLayout.LaidOutLine] = []

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
            cachedLines = TextLayout.lines(
                for: text,
                width: width,
                lineLimit: lineLimit,
                truncationMode: truncationMode
            )
            let contentWidth = cachedLines.map(\.visualWidth).max() ?? 0
            let height = max(cachedLines.count, 1)
            return Size(width: Extended(contentWidth), height: Extended(height))
        }

        override func layout(size: Size) {
            super.layout(size: size)
            let width = max(size.width.intValue, 1)
            cachedLines = TextLayout.lines(
                for: text,
                width: width,
                lineLimit: lineLimit,
                truncationMode: truncationMode
            )
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
                return max(text.width, 1)
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

    init(
        foreground: Color? = nil,
        background: Color? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        inverted: Bool? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverted = inverted
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
                inverted: attrs[Attr.InvertedAttribute.self]
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

enum TextLayout {
    static let ellipsis = "…"

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
        var current: [LaidOutLine.Unit] = []
        var currentWidth = 0

        for unit in units {
            if unit.char == "\n" {
                lines.append(LaidOutLine(units: current))
                current = []
                currentWidth = 0
                continue
            }

            let charWidth = unit.char.width
            if currentWidth + charWidth > width, !current.isEmpty {
                lines.append(LaidOutLine(units: current))
                current = [unit]
                currentWidth = charWidth
            } else {
                current.append(unit)
                currentWidth += charWidth
            }
        }
        lines.append(LaidOutLine(units: current))
        return lines
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
