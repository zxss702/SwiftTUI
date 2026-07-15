import Foundation

/// Colors can be used as views. Certain modifiers and views may also take colors as parameters.
///
/// There are different types of colors that can be used, but not all of them are supported by all
/// terminal emulators.
///
/// The named colors are ANSI colors. In many terminal emulators they are user-defined or part of a
/// theme, and bold text automatically uses the bright color variant.
public struct Color: Hashable, Sendable {
    private let data: Data

    private enum Data: Hashable, Sendable {
        case ansi(ANSIColor)
        case xterm(XTermColor)
        case trueColor(TrueColor)
    }

    private init(data: Data) {
        self.data = data
    }

    static func ansi(_ color: ANSIColor) -> Color {
        Color(data: .ansi(color))
    }

    /// A low-resolution color from a 6 by 6 by 6 color cube. The red, green and blue components
    /// must be numbers between 0 and 5.
    public static func xterm(red: Int, green: Int, blue: Int) -> Color {
        Color(data: .xterm(.color(red: red, green: green, blue: blue)))
    }

    /// A grayscale color with white value between 0 and 23.
    public static func xterm(white: Int) -> Color {
        Color(data: .xterm(.grayscale(white: white)))
    }

    /// A 24-bit color value. The red, green and blue components must be numbers between 0 and 255.
    /// Not all terminals support this.
    public static func trueColor(red: Int, green: Int, blue: Int) -> Color {
        Color(data: .trueColor(TrueColor(red: red, green: green, blue: blue)))
    }

    var foregroundEscapeSequence: String {
        switch data {
        case .ansi(let color):
            return EscapeSequence.setForegroundColor(color)
        case .trueColor(let color):
            return EscapeSequence.setForegroundColor(red: color.red, green: color.green, blue: color.blue)
        case .xterm(let color):
            return EscapeSequence.setForegroundColor(xterm: color.value)
        }
    }

    var backgroundEscapeSequence: String {
        switch data {
        case .ansi(let color):
            return EscapeSequence.setBackgroundColor(color)
        case .trueColor(let color):
            return EscapeSequence.setBackgroundColor(red: color.red, green: color.green, blue: color.blue)
        case .xterm(let color):
            return EscapeSequence.setBackgroundColor(xterm: color.value)
        }
    }

    public static var `default`: Color { Color.ansi(.default) }

    public static var black: Color { .ansi(.black) }
    public static var red: Color { .ansi(.red) }
    public static var green: Color { .ansi(.green) }
    public static var yellow: Color { .ansi(.yellow) }
    public static var blue: Color { .ansi(.blue) }
    public static var magenta: Color { .ansi(.magenta) }
    public static var cyan: Color { .ansi(.cyan) }
    public static var white: Color { .ansi(.white) }

    public static var brightBlack: Color { .ansi(.brightBlack) }
    public static var brightRed: Color { .ansi(.brightRed) }
    public static var brightGreen: Color { .ansi(.brightGreen) }
    public static var brightYellow: Color { .ansi(.brightYellow) }
    public static var brightBlue: Color { .ansi(.brightBlue) }
    public static var brightMagenta: Color { .ansi(.brightMagenta) }
    public static var brightCyan: Color { .ansi(.brightCyan) }
    public static var brightWhite: Color { .ansi(.brightWhite) }

    public static var gray: Color { .brightBlack }
}

extension Color {
    /// Bridges to the VT layer color representation. Returns `nil` for the
    /// terminal's default color (VT treats `nil` as "use default").
    var vtColor: VTColor? {
        switch data {
        case .ansi(let color):
            switch color.foregroundCode {
            case 39:
                return nil
            case 30...37:
                guard let ansi = VTANSIColor(rawValue: color.foregroundCode - 30) else { return nil }
                return .ansi(ansi, intensity: .normal)
            case 90...97:
                guard let ansi = VTANSIColor(rawValue: color.foregroundCode - 90) else { return nil }
                return .ansi(ansi, intensity: .bright)
            default:
                return nil
            }
        case .trueColor(let color):
            return .rgb(
                red: UInt8(clamping: color.red),
                green: UInt8(clamping: color.green),
                blue: UInt8(clamping: color.blue)
            )
        case .xterm(let color):
            return Color.xterm256ToRGB(color.value)
        }
    }

    /// Converts an xterm-256 palette index to its canonical RGB value.
    private static func xterm256ToRGB(_ index: Int) -> VTColor? {
        switch index {
        case 16...231:
            let value = index - 16
            let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
            let red = levels[value / 36]
            let green = levels[(value / 6) % 6]
            let blue = levels[value % 6]
            return .rgb(red: red, green: green, blue: blue)
        case 232...255:
            let gray = UInt8(8 + 10 * (index - 232))
            return .rgb(red: gray, green: gray, blue: gray)
        default:
            return nil
        }
    }
}

struct ANSIColor: Hashable {
    let foregroundCode: Int
    let backgroundCode: Int

    static var `default`: ANSIColor { ANSIColor(foregroundCode: 39, backgroundCode: 49) }

    static var black: ANSIColor { ANSIColor(foregroundCode: 30, backgroundCode: 40) }
    static var red: ANSIColor { ANSIColor(foregroundCode: 31, backgroundCode: 41) }
    static var green: ANSIColor { ANSIColor(foregroundCode: 32, backgroundCode: 42) }
    static var yellow: ANSIColor { ANSIColor(foregroundCode: 33, backgroundCode: 43) }
    static var blue: ANSIColor { ANSIColor(foregroundCode: 34, backgroundCode: 44) }
    static var magenta: ANSIColor { ANSIColor(foregroundCode: 35, backgroundCode: 45) }
    static var cyan: ANSIColor { ANSIColor(foregroundCode: 36, backgroundCode: 46) }
    static var white: ANSIColor { ANSIColor(foregroundCode: 37, backgroundCode: 47) }

    static var brightBlack: ANSIColor { ANSIColor(foregroundCode: 90, backgroundCode: 100) }
    static var brightRed: ANSIColor { ANSIColor(foregroundCode: 91, backgroundCode: 101) }
    static var brightGreen: ANSIColor { ANSIColor(foregroundCode: 92, backgroundCode: 102) }
    static var brightYellow: ANSIColor { ANSIColor(foregroundCode: 93, backgroundCode: 103) }
    static var brightBlue: ANSIColor { ANSIColor(foregroundCode: 94, backgroundCode: 104) }
    static var brightMagenta: ANSIColor { ANSIColor(foregroundCode: 95, backgroundCode: 105) }
    static var brightCyan: ANSIColor { ANSIColor(foregroundCode: 96, backgroundCode: 106) }
    static var brightWhite: ANSIColor { ANSIColor(foregroundCode: 97, backgroundCode: 107) }
}

struct XTermColor: Hashable {
    let value: Int

    static func color(red: Int, green: Int, blue: Int) -> XTermColor {
        guard red >= 0, red < 6, green >= 0, green < 6, blue >= 0, blue < 6 else {
            fatalError("Color values must lie between 1 and 5")
        }
        let offset = 16 // system colors
        return XTermColor(value: offset + (6 * 6 * red) + (6 * green) + blue)
    }

    static func grayscale(white: Int) -> XTermColor {
        guard white >= 0, white < 24 else {
            fatalError("Color value must lie between 1 and 24")
        }
        let offset = 16 + (6 * 6 * 6)
        return XTermColor(value: offset + white)
    }
}

struct TrueColor: Hashable {
    let red: Int
    let green: Int
    let blue: Int
}
