// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension UnicodeScalar {
  package var isZeroWidth: Bool {
    return switch value {
    case 0x0300 ... 0x036F, // Combining Diacritical Marks
         0x1AB0 ... 0x1AFF, // Combining Diacritical Marks Extended
         0x1DC0 ... 0x1DFF, // Combining Diacritical Marks Supplement
         0x200B ... 0x200F, // Zero Width spaces and formatting (ZWSP, ZWNJ, ZWJ, LRM, RLM)
         0x2028 ... 0x202F, // Line/Paragraph separators, LRE, RLE, PDF, LRO, RLO, NNB
         0x2060 ... 0x206F, // Word Joiner, Invisible operators
         0xFE00 ... 0xFE0F, // Variation Selectors
         0xFEFF,            // Zero Width No-Break Space
         0xE0000 ... 0xE007F, // Tags
         0xE0100 ... 0xE01EF: // Variation Selectors Supplement
      true
    default:
      false
    }
  }
  /// Determines if a unicode scalar is a wide character (occupies 2 columns)
  package var isWideCharacter: Bool {
    return switch value {
    case 0x01100 ... 0x0115f, // Hangul Jamo
         0x02329 ... 0x0232a, // Angle brackets
         0x02e80 ... 0x02eff, // CJK Radicals
         0x03000 ... 0x0303e, // CJK Symbols
         0x03041 ... 0x03096, // Hiragana
         0x030a1 ... 0x030fa, // Katakana
         0x03105 ... 0x0312d, // Bopomofo
         0x03131 ... 0x0318e, // Hangul Compatibility Jamo
         0x03190 ... 0x0319f, // Kanbun
         0x031c0 ... 0x031e3, // CJK Strokes
         0x031f0 ... 0x0321e, // Katakana Extension
         0x03220 ... 0x03247, // Enclosed CJK
         0x03250 ... 0x032fe, // Enclosed CJK
         0x03300 ... 0x04dbf, // CJK Extension A
         0x04e00 ... 0x09fff, // CJK Unified Ideographs
         0x0a960 ... 0x0a97c, // Hangul Jamo Extended-A
         0x0ac00 ... 0x0d7a3, // Hangul Syllables
         0x0f900 ... 0x0faff, // CJK Compatibility
         0x0fe10 ... 0x0fe19, // Vertical forms
         0x0fe30 ... 0x0fe6f, // CJK Compatibility Forms
         0x0ff00 ... 0x0ff60, // Fullwidth Forms
         0x0ffe0 ... 0x0ffe6, // Fullwidth Forms
         0x1f300 ... 0x1f5ff, // Misc Symbols and Pictographs
         0x1f600 ... 0x1f64f, // Emoticons
         0x1f680 ... 0x1f6ff, // Transport and Map
         0x1f700 ... 0x1f77f, // Alchemical Symbols
         0x1f780 ... 0x1f7ff, // Geometric Shapes Extended
         0x1f800 ... 0x1f8ff, // Supplemental Arrows-C
         0x1f900 ... 0x1f9ff, // Supplemental Symbols and Pictographs
         0x20000 ... 0x2fffd, // CJK Extension B-F
         0x30000 ... 0x3fffd: // CJK Extension G
      true
    default:
      false
    }
  }

  package var width: Int {
#if os(Windows)
    // Control characters have zero width
    if value < 0x20 || (0x7f ..< 0xa0).contains(value) { return 0 }
    if isZeroWidth { return 0 }
    // Windows Console renders CJK as double-width cells. GetStringTypeW's
    // C3_FULLWIDTH bit is not set for all ideographs, so rely on Unicode ranges.
    if isWideCharacter { return 2 }
    return 1
#elseif os(Linux)
    // Control characters have zero width
    if value < 0x20 || (0x7f ..< 0xa0).contains(value) { return 0 }
    if isZeroWidth { return 0 }
    return isWideCharacter ? 2 : 1
#else
    // Darwin/macOS: use wide character detection
    // Zero-width combining characters return 0
    if isZeroWidth { return 0 }
    // Wide characters (CJK, etc.) return 2
    // Normal width characters return 1
    return isWideCharacter ? 2 : 1
#endif
  }
}

extension Character {
  package var width: Int {
    // Handle common ASCII fast path
    if isASCII { return isWhitespace ? (self == " " ? 1 : 0) : 1 }
    // For non-ASCII characters, we need to check their unicode properties
    var totalWidth = 0
    for scalar in unicodeScalars {
        if scalar.isZeroWidth { continue }
        if totalWidth == 0 {
            totalWidth += scalar.width
        } else {
            if scalar.isWideCharacter {
                totalWidth = 2
            }
        }
    }
    return totalWidth == 0 ? (unicodeScalars.first?.isWideCharacter == true ? 2 : 1) : totalWidth
  }
}

extension String {
  package var width: Int {
    return unicodeScalars.reduce(0) { $0 + $1.width }
  }
}
