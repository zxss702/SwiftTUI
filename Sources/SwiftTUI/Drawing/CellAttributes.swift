import Foundation

struct CellAttributes: Equatable {
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var inverted: Bool
    /// ANSI faint（SGR 2）：降低前景强度，近似不透明度下降，不改背景色。
    var faint: Bool

    init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        inverted: Bool = false,
        faint: Bool = false
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverted = inverted
        self.faint = faint
    }
}
