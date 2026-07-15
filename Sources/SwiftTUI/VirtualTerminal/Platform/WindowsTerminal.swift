// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)

import Synchronization
import WinSDK

/// A Sendable wrapper for Windows HANDLE values.
///
/// This wrapper enables safe sharing of Windows handle values across
/// async task boundaries by marking them as `@unchecked Sendable`.
/// While HANDLE values are raw pointers, they represent opaque system
/// resources that can be safely shared in this context.
private struct SendableHANDLE: @unchecked Sendable {
  var handle: HANDLE
}

/// Windows Console API implementation of the VTTerminal protocol.
///
/// `WindowsTerminal` provides a native Windows implementation that interfaces
/// directly with the Windows Console API to enable VT100/ANSI escape sequence
/// support. It handles console mode management, input event processing, and
/// output rendering using Windows-specific system calls.
///
/// ## Windows Console Features
///
/// This implementation leverages modern Windows Console capabilities:
/// - **Virtual Terminal Processing**: Enables ANSI/VT100 escape sequence support
/// - **Input Event Handling**: Processes keyboard, mouse, and resize events
/// - **Console Mode Management**: Automatically configures and restores console settings
/// - **UTF-8 Output**: Handles Unicode text rendering through Windows APIs
///
/// ## Initialization and Setup
///
/// The terminal automatically configures the Windows console for VT100 support:
///
/// ```swift
/// // Create terminal with full interactive support
/// let terminal = try await WindowsTerminal(mode: .cooked)
///
/// // Terminal is ready for VT100 escape sequences
/// await terminal.write("\u{1B}[31mRed text\u{1B}[0m")
///
/// // Process input events
/// for await events in terminal.input {
///   for event in events {
///     switch event {
///     case .key(let keyEvent):
///       // Handle keyboard input
///       break
///     case .mouse(let mouseEvent):
///       // Handle mouse events
///       break
///     case .resize(let resizeEvent):
///       // Handle terminal resize
///       break
///     }
///   }
/// }
/// ```
///
/// ## Console Mode Management
///
/// The implementation automatically:
/// - Enables `ENABLE_VIRTUAL_TERMINAL_PROCESSING` for escape sequence support
/// - Configures `DISABLE_NEWLINE_AUTO_RETURN` for precise cursor control
/// - Preserves original console settings and restores them on cleanup
///
/// ## Thread Safety
///
/// The actor-based design ensures thread-safe access to Windows Console APIs,
/// preventing race conditions that could occur with concurrent console operations.
///
/// ## Platform Availability
///
/// This implementation is only available on Windows platforms and requires
/// Windows 10 version 1607 (Anniversary Update) or later for full VT100 support.
internal final actor WindowsTerminal: VTTerminal {
  private let hIn: SendableHANDLE
  private let hOut: SendableHANDLE
  private let dwOutMode: DWORD
  private let dwInMode: DWORD
  private let interceptsCtrlC: Bool

  /// Stream of terminal input events from Windows Console API.
  ///
  /// This stream processes Windows console input events (keyboard, mouse,
  /// resize) and converts them to VTEvent instances. The stream operates
  /// asynchronously and continues until the terminal is deallocated or
  /// an unrecoverable error occurs.
  public nonisolated let input: VTEventStream

  /// Current terminal dimensions in character units.
  ///
  /// This property reflects the console window size (not the buffer size)
  /// and is updated automatically when console resize events are processed.
  /// The size represents the visible character grid available for output.
  private let _size: Mutex<Size>
  public nonisolated var size: Size {
    return _size.withLock { $0 }
  }

  /// Creates a new Windows terminal interface with the specified mode.
  ///
  /// This initializer configures the Windows console for VT100 compatibility
  /// and sets up input event processing. It automatically enables virtual
  /// terminal processing and configures appropriate console modes.
  ///
  /// ## Parameters
  /// - mode: The terminal interaction mode (typically `.cooked` for full functionality)
  ///
  /// ## Setup Process
  /// 1. Obtains standard input/output handles
  /// 2. Queries current console configuration
  /// 3. Determines terminal dimensions from console buffer info
  /// 4. Enables VT100 escape sequence processing
  /// 5. Starts asynchronous input event monitoring
  ///
  /// ## Usage Example
  /// ```swift
  /// do {
  ///   let terminal = try await WindowsTerminal(mode: .cooked)
  ///
  ///   // Terminal is ready for VT100 sequences
  ///   await terminal.write("\u{1B}[2J\u{1B}[H")  // Clear screen
  ///   await terminal.write("Welcome to Windows Terminal!")
  ///
  ///   // Process input events
  ///   for await events in terminal.input {
  ///     // Handle user input
  ///   }
  /// } catch {
  ///   print("Failed to initialize terminal: \(error)")
  /// }
  /// ```
  ///
  /// ## Error Conditions
  /// Throws `WindowsError` if:
  /// - Standard handles cannot be obtained
  /// - Console mode queries or configuration fail
  /// - Console screen buffer information is unavailable
  ///
  /// ## Console Mode Changes
  /// The initializer modifies the console output mode to enable:
  /// - `ENABLE_VIRTUAL_TERMINAL_PROCESSING`: VT100/ANSI escape sequences
  /// - `DISABLE_NEWLINE_AUTO_RETURN`: Precise cursor positioning
  ///
  /// Original console modes are preserved and restored during cleanup.
  public init(mode: VTMode) async throws {
    self.hIn = SendableHANDLE(handle: GetStdHandle(STD_INPUT_HANDLE))
    if self.hIn.handle == INVALID_HANDLE_VALUE {
      throw WindowsError()
    }

    self.hOut = SendableHANDLE(handle: GetStdHandle(STD_OUTPUT_HANDLE))
    if self.hOut.handle == INVALID_HANDLE_VALUE {
      throw WindowsError()
    }

    var dwOutMode: DWORD = 0
    guard GetConsoleMode(self.hOut.handle, &dwOutMode) else {
      throw WindowsError()
    }

    var dwInMode: DWORD = 0
    guard GetConsoleMode(self.hIn.handle, &dwInMode) else {
      throw WindowsError()
    }

    var csbi = CONSOLE_SCREEN_BUFFER_INFO()
    guard GetConsoleScreenBufferInfo(self.hOut.handle, &csbi) else {
      throw WindowsError()
    }

    let size = Size(width: Int(csbi.srWindow.Right - csbi.srWindow.Left + 1),
                    height: Int(csbi.srWindow.Bottom - csbi.srWindow.Top + 1))
    _size = Mutex(size)

    // Save the original console modes so that we can restore them later.
    self.dwOutMode = dwOutMode
    self.dwInMode = dwInMode

    let interceptsCtrlC: Bool
    switch mode {
    case .raw:
      var rawInMode = dwInMode
      rawInMode &= ~(DWORD(ENABLE_ECHO_INPUT) | DWORD(ENABLE_LINE_INPUT) | DWORD(ENABLE_PROCESSED_INPUT))
      rawInMode &= ~DWORD(0x0040) /* ENABLE_QUICK_EDIT_MODE */
      rawInMode |= DWORD(ENABLE_WINDOW_INPUT) | DWORD(0x0010) /* ENABLE_MOUSE_INPUT */ | DWORD(0x0080) /* ENABLE_EXTENDED_FLAGS */
      guard SetConsoleMode(self.hIn.handle, rawInMode) else {
        throw WindowsError()
      }
      FlushConsoleInputBuffer(self.hIn.handle)
      WindowsConsoleCtrlHandler.install(stdin: self.hIn.handle)
      interceptsCtrlC = true
    case .canonical:
      interceptsCtrlC = false
    }
    self.interceptsCtrlC = interceptsCtrlC

    dwOutMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN
    guard SetConsoleMode(self.hOut.handle, dwOutMode) else {
      throw WindowsError()
    }

    // See POSIXTerminal: never drop key/click batches under mouse-move flood.
    self.input = VTEventStream(AsyncThrowingStream(bufferingPolicy: .unbounded) { [hIn, hOut] continuation in
      Task {
        repeat {
          do {
            guard WaitForSingleObject(hIn.handle, INFINITE) == WAIT_OBJECT_0 else {
              throw WindowsError()
            }

            var cNumberOfEvents: DWORD = 0
            guard GetNumberOfConsoleInputEvents(hIn.handle, &cNumberOfEvents) else {
              throw WindowsError()
            }
            guard cNumberOfEvents > 0 else { continue }

            let events = try Array<INPUT_RECORD>(unsafeUninitializedCapacity: Int(cNumberOfEvents)) {
              var NumberOfEventsRead: DWORD = 0
              guard ReadConsoleInputW(hIn.handle, $0.baseAddress, DWORD($0.count), &NumberOfEventsRead) else {
                throw WindowsError()
              }
              $1 = Int(NumberOfEventsRead)
            }
            .compactMap { record -> VTEvent? in
              switch record.EventType {
              case KEY_EVENT:
                guard record.Event.KeyEvent.bKeyDown == true else { return nil }
                return VTEvent.key(.from(record.Event.KeyEvent))
              case MOUSE_EVENT:
                return VTEvent.mouse(.from(record.Event.MouseEvent))
              case WINDOW_BUFFER_SIZE_EVENT:
                var csbi = CONSOLE_SCREEN_BUFFER_INFO()
                guard GetConsoleScreenBufferInfo(hOut.handle, &csbi) else {
                  return VTEvent.resize(.from(record.Event.WindowBufferSizeEvent))
                }
                let windowSize = Size(
                  width: Int(csbi.srWindow.Right - csbi.srWindow.Left + 1),
                  height: Int(csbi.srWindow.Bottom - csbi.srWindow.Top + 1)
                )
                return VTEvent.resize(ResizeEvent(size: windowSize))
              default:
                return nil
              }
            }

            let coalesced = VTEvent.coalescingMouseMoves(events)
            if !coalesced.isEmpty {
              continuation.yield(coalesced)
            }
          } catch {
            continuation.finish(throwing: error)
          }
        } while !Task.isCancelled
        continuation.finish()
      }
    })
  }

  deinit {
    if interceptsCtrlC {
      WindowsConsoleCtrlHandler.uninstall()
    }
    // Restore the original console modes.
    _ = SetConsoleMode(self.hOut.handle, self.dwOutMode)
    _ = SetConsoleMode(self.hIn.handle, self.dwInMode)
  }

  /// Writes string data directly to the Windows console output.
  ///
  /// This method sends UTF-8 encoded string data to the console using the
  /// Windows `WriteFile` API. The string can contain VT100/ANSI escape
  /// sequences which will be processed by the console if virtual terminal
  /// processing is enabled.
  ///
  /// ## Parameters
  /// - string: The text to write, including any escape sequences
  ///
  /// ## Usage Examples
  /// ```swift
  /// // Write plain text
  /// await terminal.write("Hello, World!")
  ///
  /// // Write with ANSI color codes
  /// await terminal.write("\u{1B}[31mRed text\u{1B}[0m")
  ///
  /// // Complex escape sequences
  /// await terminal.write("\u{1B}[2J\u{1B}[H")  // Clear screen, home cursor
  /// ```
  ///
  /// ## Performance Characteristics
  /// The method performs synchronous I/O to the console. For high-frequency
  /// output, consider using `VTBufferedTerminalStream` to batch multiple
  /// writes and reduce system call overhead.
  ///
  /// ## Error Handling
  /// Write failures are silently ignored in this implementation. The
  /// Windows `WriteFile` API may fail if the console handle is invalid
  /// or the process lacks write permissions.
  internal func write(_ string: consuming String) {
    var dwNumberOfBytesWritten: DWORD = 0
    _ = string.withUTF8 {
      WriteFile(self.hOut.handle, $0.baseAddress, DWORD($0.count), &dwNumberOfBytesWritten, nil)
    }
  }
}

/// Convenience operators for Windows terminal output.
extension WindowsTerminal {
  /// Writes a string to the terminal using operator syntax.
  ///
  /// This operator provides a fluent interface for terminal output that
  /// mirrors common stream operator patterns. It's particularly useful
  /// for chaining multiple output operations in sequence.
  ///
  /// ## Parameters
  /// - terminal: The Windows terminal to write to
  /// - string: The text content to write
  ///
  /// ## Returns
  /// The same terminal instance, enabling method chaining.
  ///
  /// ## Usage Example
  /// ```swift
  /// // Chain multiple writes
  /// await terminal <<< "Line 1\n"
  ///                <<< "Line 2\n"
  ///                <<< "\u{1B}[31mRed Line 3\u{1B}[0m\n"
  ///
  /// // Equivalent to multiple write() calls
  /// await terminal.write("Line 1\n")
  /// await terminal.write("Line 2\n")
  /// await terminal.write("\u{1B}[31mRed Line 3\u{1B}[0m\n")
  /// ```
  ///
  /// ## Performance Notes
  /// Each operator call results in a separate `WriteFile` system call.
  /// For bulk output, consider accumulating strings or using buffered
  /// output streams for better performance.
  @discardableResult
  public static func <<< (_ terminal: WindowsTerminal, _ string: String) async -> WindowsTerminal {
    await terminal.write(string)
    return terminal
  }
}

#endif
