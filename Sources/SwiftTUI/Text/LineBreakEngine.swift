import Foundation

// MARK: - Line Break Property (UAX #14)

/// Unicode line break class used by the simplified UAX #14 pair rules.
enum LineBreakProperty: UInt8 {
    case bk, cr, lf, nl, sp, zw, wj, gl, ba, hy, op, cl, cp, ex, is_, quot, ns, al, nu, id, cj, unknown
}

extension UnicodeScalar {
    var lineBreakProperty: LineBreakProperty {
        switch value {
        case 0x000A: return .lf
        case 0x000D: return .cr
        case 0x000B, 0x000C: return .bk
        case 0x0020, 0x0009: return .sp
        case 0x00A0, 0x202F: return .gl
        case 0x2010: return .hy
        case 0x2011, 0x2012, 0x2013, 0x2014, 0x2015: return .ba
        case 0x2028: return .nl
        case 0x2029: return .bk
        case 0x200B: return .zw
        case 0x2060, 0xFEFF: return .wj
        case 0x0021, 0x00A1, 0xFE56: return .ex
        case 0x003F, 0x00BF, 0xFE16: return .ex
        case 0x002E, 0x002C, 0x003A, 0x003B: return .is_
        case 0x0028, 0xFF08: return .op
        case 0x005B, 0xFF3B: return .op
        case 0x007B, 0xFF5B: return .op
        case 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A: return .op
        case 0x0029, 0xFF09: return .cp
        case 0x005D, 0xFF3D: return .cp
        case 0x007D, 0xFF5D: return .cp
        case 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B: return .cp
        case 0x0022, 0x0027, 0x00AB, 0x00BB: return .quot
        case 0x2018, 0x2019, 0x201C, 0x201D, 0xFF02, 0xFF07: return .quot
        case 0x0030 ... 0x0039: return .nu
        case 0x0041 ... 0x005A, 0x0061 ... 0x007A: return .al
        case 0x00B7, 0x2016, 0x2022, 0x2027, 0x30FB: return .ns
        case 0x3001, 0x3002, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B: return .cl
        case 0xFF01, 0xFF1F: return .ex
        case 0x3040 ... 0x309F, 0x30A0 ... 0x30FF: return .cj
        case 0x1100 ... 0x11FF, 0xAC00 ... 0xD7A3: return .id
        case 0x2E80 ... 0x2FFF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF, 0x20000 ... 0x2FFFF, 0x30000 ... 0x3FFFF:
            return .id
        case 0xFF10 ... 0xFF19: return .nu
        case 0xFF21 ... 0xFF3A, 0xFF41 ... 0xFF5A: return .al
        default:
            if isWideCharacter { return .id }
            if Character(self).isLetter { return .al }
            if Character(self).isNumber { return .nu }
            return .unknown
        }
    }
}

extension Character {
    fileprivate var lineBreakProperty: LineBreakProperty {
        for scalar in unicodeScalars where !scalar.isZeroWidth {
            return scalar.lineBreakProperty
        }
        return .unknown
    }

    fileprivate var isIdeographicForLineBreak: Bool {
        switch lineBreakProperty {
        case .id, .cj: return true
        default: return false
        }
    }
}

// MARK: - LineBreakEngine

/// UAX #14-inspired line break opportunities with CJK kinsoku (避头尾) rules.
enum LineBreakEngine {
    /// Whether a mandatory line break occurs at this character.
    static func isMandatoryBreak(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            switch scalar.lineBreakProperty {
            case .bk, .lf, .nl: return true
            default: continue
            }
        }
        return char == "\n" || char == "\u{2028}" || char == "\u{2029}"
    }

    /// Whether a soft break is allowed between `left` and `right`.
    static func canBreak(after left: Character, before right: Character) -> Bool {
        let leftProp = left.lineBreakProperty
        let rightProp = right.lineBreakProperty

        if leftProp == .cr, rightProp == .lf { return false }
        if rightProp == .bk || rightProp == .lf || rightProp == .nl { return false }
        if leftProp == .wj || rightProp == .wj { return false }
        if leftProp == .gl || rightProp == .gl { return false }
        if leftProp == .zw { return true }

        // LB15: do not break after opening punctuation / quotes.
        if leftProp == .op || leftProp == .quot { return false }

        // LB21: do not break before closing punctuation / exclamation.
        if rightProp == .cl || rightProp == .cp || rightProp == .ex { return false }

        // LB8a: do not break inside words or numbers.
        if isAlphaNumeric(leftProp), isAlphaNumeric(rightProp) { return false }

        // Break after spaces and break-after punctuation.
        if leftProp == .sp || leftProp == .ba { return true }

        // Break after hyphens.
        if leftProp == .hy { return true }

        // CJK ideographs may break between each other.
        if left.isIdeographicForLineBreak, right.isIdeographicForLineBreak { return true }

        // Mixed script boundaries.
        if left.isIdeographicForLineBreak || right.isIdeographicForLineBreak { return true }

        // Infix separators.
        if leftProp == .is_ || rightProp == .is_ { return true }

        return false
    }

    /// Characters that must not appear at the start of a line (kinsoku / pushOut).
    static func isLineStartProhibited(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            switch scalar.value {
            case 0x0021, 0x0029, 0x002C, 0x002E, 0x003A, 0x003B, 0x003F,
                 0x00A1, 0x00B0, 0x00B4, 0x00B7, 0x00BB, 0x00BF,
                 0x2019, 0x201D, 0x2022, 0x2025, 0x2026, 0x2030, 0x2032, 0x2033,
                 0x203C, 0x2047, 0x2048, 0x2049,
                 0x3001, 0x3002, 0x3003, 0x3005,
                 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015,
                 0xFE50, 0xFE51, 0xFE52, 0xFE54, 0xFE55, 0xFE56, 0xFE57, 0xFE58, 0xFE59, 0xFE5A,
                 0xFE5B, 0xFE5C, 0xFE5D, 0xFE5E,
                 0xFF01, 0xFF02, 0xFF05, 0xFF07, 0xFF09, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F,
                 0xFF3D, 0xFF40, 0xFF5C, 0xFF5D, 0xFF5E, 0xFF60, 0xFF61, 0xFF63, 0xFF64, 0xFF65:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Characters that must not appear at the end of a line (kinsoku / pushOut).
    static func isLineEndProhibited(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            switch scalar.value {
            case 0x0028, 0x005B, 0x007B, 0x00AB, 0x2018, 0x201C,
                 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A,
                 0xFE59, 0xFE5B, 0xFE5D,
                 0xFF08, 0xFF3B, 0xFF5B, 0xFF62, 0xFF64:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Choose where the next line should start when `exclusiveEnd` does not fit.
    ///
    /// - Returns: Index in `units` where the next line begins. Current line is `units[lineStart..<result]`.
    static func chooseBreakPoint(
        units: [TextLayout.LaidOutLine.Unit],
        lineStart: Int,
        exclusiveEnd: Int,
        lastOpportunity: Int?
    ) -> Int {
        if let opportunity = lastOpportunity,
           opportunity >= lineStart,
           opportunity < exclusiveEnd
        {
            var breakAfter = opportunity
            while breakAfter >= lineStart {
                let nextIndex = breakAfter + 1
                if nextIndex < units.count, isLineStartProhibited(units[nextIndex].char) {
                    if breakAfter > lineStart {
                        breakAfter -= 1
                        continue
                    }
                }
                break
            }
            while breakAfter >= lineStart, isLineEndProhibited(units[breakAfter].char) {
                breakAfter -= 1
            }
            if breakAfter >= lineStart {
                return breakAfter + 1
            }
        }
        return exclusiveEnd
    }

    private static func isAlphaNumeric(_ property: LineBreakProperty) -> Bool {
        property == .al || property == .nu
    }
}
