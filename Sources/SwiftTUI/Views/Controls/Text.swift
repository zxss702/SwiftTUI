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
        node.element = TextElement(
            text: displayString,
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
        control.text = displayString
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

    private var displayString: String {
        if #available(macOS 12, *), let attributedText {
            return String(attributedText.characters)
        }
        return text ?? ""
    }

    private class TextElement: Element {
        var text: String
        var foregroundColor: Color
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var strikethrough: Bool
        var lineLimit: Int?
        var truncationMode: Text.TruncationMode

        private var cachedLines: [String] = []

        init(
            text: String,
            foregroundColor: Color,
            bold: Bool,
            italic: Bool,
            underline: Bool,
            strikethrough: Bool,
            lineLimit: Int?,
            truncationMode: Text.TruncationMode
        ) {
            self.text = text
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
            let contentWidth = cachedLines.map(\.width).max() ?? 0
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
            let attributes = CellAttributes(
                bold: bold,
                italic: italic,
                underline: underline,
                strikethrough: strikethrough
            )

            for lineIndex in 0 ..< maxHeight {
                var currentWidth = 0
                if lineIndex < cachedLines.count {
                    let line = cachedLines[lineIndex]
                    for char in line {
                        let charWidth = char.width
                        if charWidth <= 0 {
                            if char == "\t", currentWidth < maxWidth {
                                buffer.setCell(
                                    Cell(char: " ", foregroundColor: foregroundColor, attributes: attributes),
                                    at: Position(column: Extended(currentWidth), line: Extended(lineIndex))
                                )
                                currentWidth += 1
                            }
                            continue
                        }
                        if currentWidth + charWidth > maxWidth { break }
                        buffer.setCell(
                            Cell(char: char, foregroundColor: foregroundColor, attributes: attributes),
                            at: Position(column: Extended(currentWidth), line: Extended(lineIndex))
                        )
                        if charWidth > 1 {
                            for w in 1 ..< charWidth {
                                buffer.setCell(
                                    Cell(char: "\u{0000}", foregroundColor: foregroundColor, attributes: attributes),
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

        private func resolvedWidth(proposedSize: Size) -> Int {
            if proposedSize.width == .infinity {
                // 无宽度约束时按单行完整内容测量；lineLimit 只限制高度行数
                return max(text.width, 1)
            }
            return max(proposedSize.width.intValue, 1)
        }
    }
}

// MARK: - TextLayout

enum TextLayout {
    static let ellipsis = "…"

    static func lines(
        for text: String,
        width: Int,
        lineLimit: Int?,
        truncationMode: Text.TruncationMode
    ) -> [String] {
        let width = max(width, 1)
        let wrapped = wrap(text, width: width)

        guard let limit = lineLimit else {
            return wrapped.isEmpty ? [""] : wrapped
        }

        if limit <= 0 {
            return []
        }

        if wrapped.count <= limit {
            return wrapped
        }

        switch truncationMode {
        case .tail:
            return truncateTail(text: text, width: width, maxLines: limit)
        case .head:
            return truncateHead(text: text, width: width, maxLines: limit)
        case .middle:
            return truncateMiddle(text: text, width: width, maxLines: limit)
        }
    }

    /// 按可视宽度软换行（支持显式 `\n`）。
    static func wrap(_ text: String, width: Int) -> [String] {
        guard !text.isEmpty else { return [""] }

        var lines: [String] = []
        var current = ""
        var currentWidth = 0

        for char in text {
            if char == "\n" {
                lines.append(current)
                current = ""
                currentWidth = 0
                continue
            }

            let charWidth = char.width
            if currentWidth + charWidth > width, !current.isEmpty {
                lines.append(current)
                current = String(char)
                currentWidth = charWidth
            } else {
                current.append(char)
                currentWidth += charWidth
            }
        }
        lines.append(current)
        return lines
    }

    private static func truncateTail(text: String, width: Int, maxLines: Int) -> [String] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let prefix = prefixFitting(text, maxWidth: budget)
        return capped(wrap(prefix + ellipsis, width: width), maxLines: maxLines)
    }

    private static func truncateHead(text: String, width: Int, maxLines: Int) -> [String] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let suffix = suffixFitting(text, maxWidth: budget)
        return capped(wrap(ellipsis + suffix, width: width), maxLines: maxLines)
    }

    private static func truncateMiddle(text: String, width: Int, maxLines: Int) -> [String] {
        let budget = max(width * maxLines - ellipsis.width, 0)
        let left = budget / 2
        let right = budget - left
        let prefix = prefixFitting(text, maxWidth: left)
        let suffix = suffixFitting(text, maxWidth: right)
        return capped(wrap(prefix + ellipsis + suffix, width: width), maxLines: maxLines)
    }

    private static func capped(_ lines: [String], maxLines: Int) -> [String] {
        Array(lines.prefix(maxLines))
    }

    private static func prefixFitting(_ string: String, maxWidth: Int) -> String {
        var result = ""
        var width = 0
        for char in string {
            if char == "\n" {
                // 换行占满当前视觉行剩余，这里按 1 宽计入预算以保持简单
                if width + 1 > maxWidth { break }
                result.append(char)
                width += 1
                continue
            }
            let charWidth = char.width
            if width + charWidth > maxWidth { break }
            result.append(char)
            width += charWidth
        }
        return result
    }

    private static func suffixFitting(_ string: String, maxWidth: Int) -> String {
        var result = ""
        var width = 0
        for char in string.reversed() {
            if char == "\n" {
                if width + 1 > maxWidth { break }
                result.insert(char, at: result.startIndex)
                width += 1
                continue
            }
            let charWidth = char.width
            if width + charWidth > maxWidth { break }
            result.insert(char, at: result.startIndex)
            width += charWidth
        }
        return result
    }
}
