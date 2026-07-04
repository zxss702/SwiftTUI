// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)

import WinSDK

private var windowsConsoleCtrlStdinHandle: HANDLE?
private var windowsConsoleCtrlHandler: (@convention(c) (DWORD) -> WindowsBool)?

/// Intercepts Windows console Ctrl+C / Ctrl+Break so they reach the TUI as
/// key events instead of terminating the process (POSIX raw mode disables ISIG
/// for the same effect).
enum WindowsConsoleCtrlHandler {
  static func install(stdin: HANDLE) {
    windowsConsoleCtrlStdinHandle = stdin

    let handler: @convention(c) (DWORD) -> WindowsBool = { type in
      switch type {
      case DWORD(CTRL_C_EVENT), DWORD(CTRL_BREAK_EVENT):
        if let stdin = windowsConsoleCtrlStdinHandle {
          injectWindowsConsoleInterrupt(into: stdin)
        }
        return true
      default:
        return false
      }
    }

    windowsConsoleCtrlHandler = handler
    _ = SetConsoleCtrlHandler(handler, true)
  }

  static func uninstall() {
    _ = SetConsoleCtrlHandler(nil, true)
    windowsConsoleCtrlHandler = nil
    windowsConsoleCtrlStdinHandle = nil
  }
}

private func injectWindowsConsoleInterrupt(into handle: HANDLE) {
  var record = INPUT_RECORD()
  record.EventType = WORD(KEY_EVENT)
  record.Event.KeyEvent.bKeyDown = true
  record.Event.KeyEvent.wRepeatCount = 1
  record.Event.KeyEvent.wVirtualKeyCode = 0x43 // 'C'
  record.Event.KeyEvent.wVirtualScanCode = 0
  record.Event.KeyEvent.uChar.UnicodeChar = WCHAR(3)
  record.Event.KeyEvent.dwControlKeyState = DWORD(LEFT_CTRL_PRESSED)

  var written: DWORD = 0
  _ = withUnsafePointer(to: &record) { pointer in
    WriteConsoleInputW(handle, UnsafeMutablePointer(mutating: pointer), 1, &written)
  }
}

#endif
