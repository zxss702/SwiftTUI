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

  /// Scalars that force emoji presentation / join emoji ZWJ sequences.
  /// Kept so input layers can accept them even when `width == 0`.
  package var isEmojiFormatScalar: Bool {
    switch value {
    case 0x200D,           // ZWJ
         0xFE0E, 0xFE0F,   // text / emoji variation selectors
         0x20E3,           // combining enclosing keycap
         0x1F3FB ... 0x1F3FF: // emoji skin-tone modifiers
      return true
    default:
      return false
    }
  }

  /// Determines if a unicode scalar is a wide character (occupies 2 columns)
  package var isWideCharacter: Bool {
    return switch value {
    case 0x01100 ... 0x0115f, // Hangul Jamo
         0x0231A ... 0x0231B, // Watch / Hourglass (emoji)
         0x02329 ... 0x0232a, // Angle brackets
         0x023E9 ... 0x023EC, // Media control emoji
         0x023F0, 0x023F3,    // Alarm / Hourglass
         0x025FD ... 0x025FE, // Squares
         0x02600 ... 0x026FF, // Misc symbols (many emoji: ⭐ ☀ ⚡ ❤ …)
         0x02700 ... 0x027BF, // Dingbats (✅ ✨ ✂ …)
         0x02B1B ... 0x02B1C, // Black/White large squares
         0x02B50, 0x02B55,    // Star / Circle
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
         0x1F000 ... 0x1F02F, // Mahjong
         0x1F0A0 ... 0x1F0FF, // Playing cards
         0x1F100 ... 0x1F1FF, // Enclosed alphanumerics / regional indicators
         0x1f300 ... 0x1f5ff, // Misc Symbols and Pictographs
         0x1f600 ... 0x1f64f, // Emoticons
         0x1f680 ... 0x1f6ff, // Transport and Map
         0x1f700 ... 0x1f77f, // Alchemical Symbols
         0x1f780 ... 0x1f7ff, // Geometric Shapes Extended
         0x1f800 ... 0x1f8ff, // Supplemental Arrows-C
         0x1f900 ... 0x1f9ff, // Supplemental Symbols and Pictographs
         0x1fa00 ... 0x1faff, // Symbols and Pictographs Extended-A
         0x20000 ... 0x2fffd, // CJK Extension B-F
         0x30000 ... 0x3fffd: // CJK Extension G
      true
    default:
      false
    }
  }

  package var width: Int {
    // Darwin/macOS: use wide character detection
    // Zero-width combining characters return 0
    if isZeroWidth { return 0 }
    // Skin-tone modifiers are format scalars that are themselves wide in
    // isolation, but only contribute inside an emoji cluster (handled at
    // Character level). Treat them as zero-width when measured alone so
    // String/Character cluster width stays correct.
    if (0x1F3FB ... 0x1F3FF).contains(value) { return 0 }
    // Wide characters (CJK, emoji, …) return 2
    // Normal width characters return 1
    return isWideCharacter ? 2 : 1
  }
}

extension Character {
  /// Terminal cell width of this extended grapheme cluster.
  ///
  /// Emoji ZWJ sequences, skin tones and VS16 (`U+FE0F`) presentation forms
  /// always occupy 2 columns — matching modern terminal emulators.
  package var width: Int {
    // Handle common ASCII fast path
    if isASCII { return isWhitespace ? (self == " " ? 1 : 0) : 1 }

    let scalars = unicodeScalars

    // Single-scalar fast path (the vast majority of CJK / Latin text): emoji
    // sequence detection (ZWJ / VS16 / keycap / flag / skin-tone) all require
    // multiple scalars, so a lone scalar's own width is authoritative. This
    // skips the `Array(unicodeScalars)` allocation + range scans in
    // `hasEmojiTerminalWidth` for every character during wrapping.
    var iterator = scalars.makeIterator()
    guard let first = iterator.next() else { return 1 }
    if iterator.next() == nil, !first.isEmojiFormatScalar {
      // Lone emoji-format scalars (skin tone / VS16 / ZWJ) keep the full
      // cluster logic below; everything else uses its own scalar width.
      return first.width
    }

    if scalars.allSatisfy(\.isZeroWidth) { return 0 }

    // Emoji presentation / ZWJ / keycap / flag clusters → always 2 cells.
    if hasEmojiTerminalWidth { return 2 }

    var totalWidth = 0
    for scalar in scalars {
      if scalar.isZeroWidth || scalar.isEmojiFormatScalar { continue }
      totalWidth = max(totalWidth, scalar.width)
    }
    return totalWidth == 0 ? 1 : totalWidth
  }

  /// Whether this cluster should be rendered double-width like an emoji glyph.
  private var hasEmojiTerminalWidth: Bool {
    let scalars = Array(unicodeScalars)
    // VS16 forces emoji presentation (⭐️ ❤️ ☀️ …).
    if scalars.contains(where: { $0.value == 0xFE0F }) { return true }
    // ZWJ sequences (👨‍👩‍👧 🏳️‍🌈 …).
    if scalars.contains(where: { $0.value == 0x200D }) { return true }
    // Keycaps (1️⃣ #️⃣).
    if scalars.contains(where: { $0.value == 0x20E3 }) { return true }
    // Regional-indicator flags (🇺🇸).
    if scalars.contains(where: { (0x1F1E6 ... 0x1F1FF).contains($0.value) }) { return true }
    // Skin-tone modified emoji (👍🏻).
    if scalars.contains(where: { (0x1F3FB ... 0x1F3FF).contains($0.value) }) { return true }
    // Base scalar already in an emoji / wide pictograph range.
    for scalar in scalars where !scalar.isZeroWidth {
      if scalar.isWideCharacter && scalar.value >= 0x1F000 { return true }
      // Misc symbols / dingbats that are commonly emoji even without VS16.
      if (0x2600 ... 0x27BF).contains(scalar.value) { return true }
      if scalar.value == 0x2B50 || scalar.value == 0x2B55 { return true }
      if (0x231A ... 0x231B).contains(scalar.value) { return true }
      if (0x23E9 ... 0x23EC).contains(scalar.value) { return true }
      if scalar.value == 0x23F0 || scalar.value == 0x23F3 { return true }
    }
    return false
  }
}

extension String {
  /// Sum of per-`Character` terminal widths (grapheme clusters), never raw
  /// scalar widths — ZWJ emoji would otherwise look 3–6 cells wide.
  package var width: Int {
    reduce(0) { $0 + $1.width }
  }
}
