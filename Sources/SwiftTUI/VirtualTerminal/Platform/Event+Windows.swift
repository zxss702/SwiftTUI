// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)

import WinSDK

extension KeyModifiers {
  internal static func from(_ dwControlKeyState: DWORD) -> KeyModifiers {
    KeyModifiers([
      dwControlKeyState & SHIFT_PRESSED == SHIFT_PRESSED ? .shift : nil,
      dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED) == 0 ? nil : .alt,
      dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED) == 0 ? nil : .ctrl,
    ].compactMap { $0 })
  }
}

extension KeyEvent {
  internal static func from(_ record: KEY_EVENT_RECORD) -> KeyEvent {
    let unicodeChar = record.uChar.UnicodeChar
    // unicodeChar == 0 means no character (e.g. bare Ctrl/Shift/Alt press).
    // Map Windows Backspace (0x08, BS) -> 0x7F (DEL) to match macOS/Linux convention.
    let scalar: UnicodeScalar? = switch unicodeChar {
      case 0:    nil       // modifier-only key press, no character
      case 0x08: "\u{7F}"  // Windows Backspace -> DEL (matches macOS/Linux)
      default:   UnicodeScalar(unicodeChar)
    }
    return KeyEvent(scalar: scalar,
                    keycode: record.wVirtualKeyCode,
                    modifiers: .from(record.dwControlKeyState),
                    type: record.bKeyDown == true ? .press : .release)
  }
}


extension MouseEventType {
  internal static func from(_ record: MOUSE_EVENT_RECORD) -> MouseEventType {
    // TODO(compnerd) differentiate between button press/release
    switch record.dwEventFlags {
    case MOUSE_MOVED:
      return .move
    case MOUSE_WHEELED:
      return .scroll(deltaX: 0, deltaY: -Int(Int16(bitPattern: HIWORD(record.dwButtonState))) / 120)
    case MOUSE_HWHEELED:
      return .scroll(deltaX: Int(Int16(bitPattern: HIWORD(record.dwButtonState))) / 120, deltaY: 0)
    default:
      let buttons = MouseButton([
        record.dwButtonState & FROM_LEFT_1ST_BUTTON_PRESSED == 0 ? nil : .left,
        record.dwButtonState & RIGHTMOST_BUTTON_PRESSED == 0 ? nil : .right,
        record.dwButtonState & FROM_LEFT_2ND_BUTTON_PRESSED == 0 ? nil : .middle,
      ].compactMap { $0 })
      return buttons.isEmpty ? .released(.left) : .pressed(buttons)
    }
  }
}

extension MouseEvent {
  internal static func from(_ record: MOUSE_EVENT_RECORD) -> MouseEvent {
    MouseEvent(position: Position(x: Int(record.dwMousePosition.X), y: Int(record.dwMousePosition.Y)),
               type: .from(record))
  }
}

extension ResizeEvent {
  internal static func from(_ record: WINDOW_BUFFER_SIZE_RECORD) -> ResizeEvent {
    ResizeEvent(size: Size(width: Int(record.dwSize.X), height: Int(record.dwSize.Y)))
  }
}

#endif
