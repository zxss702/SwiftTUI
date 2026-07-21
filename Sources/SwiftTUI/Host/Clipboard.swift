import Foundation

#if os(Windows)
import WinSDK
#endif

/// Writes text to the system clipboard.
///
/// Two channels are used together:
/// - **OSC 52** through the pty: works in iTerm2, kitty, Ghostty, WezTerm,
///   Alacritty, tmux — and across ssh sessions. Apple's Terminal.app ignores
///   it, hence the second channel.
/// - **Local pasteboard**:
///   - macOS: `pbcopy`
///   - Linux: `wl-copy` / `xclip` / `xsel` when present
///   - Windows: Win32 `SetClipboardData(CF_UNICODETEXT)` (no child process)
@MainActor
enum Clipboard {
    static func copy(_ text: String, vtRenderer: VTRenderer?) {
        guard !text.isEmpty else { return }
        if let terminal = vtRenderer?.terminalIfAvailable {
            let payload = Data(text.utf8).base64EncodedString()
            let sequence = "\u{1B}]52;c;\(payload)\u{07}"
            Task {
                await terminal.write(sequence)
            }
        }
        copyViaLocalPasteboard(text)
    }

    private static func copyViaLocalPasteboard(_ text: String) {
        #if os(Windows)
        copyViaWin32(text)
        #elseif os(macOS)
        copyViaProcess(candidates: [["/usr/bin/pbcopy"]], text: text)
        #elseif os(Linux)
        copyViaProcess(
            candidates: [
                ["/usr/bin/wl-copy"],
                ["/usr/bin/xclip", "-selection", "clipboard"],
                ["/usr/bin/xsel", "--clipboard", "--input"],
            ],
            text: text
        )
        #else
        _ = text
        #endif
    }

    #if os(Windows)
    private static func copyViaWin32(_ text: String) {
        // Win32 clipboard APIs are not MainActor-bound; keep them off the
        // input path so a stuck clipboard lock cannot freeze the TUI.
        DispatchQueue.global(qos: .userInitiated).async {
            let chars = Array(text.utf16)
            let bytes = (chars.count + 1) * MemoryLayout<WCHAR>.size
            guard let global = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)) else { return }
            guard let locked = GlobalLock(global) else {
                GlobalFree(global)
                return
            }
            chars.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    memcpy(locked, base, chars.count * MemoryLayout<WCHAR>.size)
                }
                // Null-terminate.
                locked.storeBytes(of: WCHAR(0), toByteOffset: chars.count * MemoryLayout<WCHAR>.size, as: WCHAR.self)
            }
            GlobalUnlock(global)

            guard OpenClipboard(nil) else {
                GlobalFree(global)
                return
            }
            defer { CloseClipboard() }
            EmptyClipboard()
            if SetClipboardData(UINT(CF_UNICODETEXT), global) == nil {
                GlobalFree(global)
            }
            // On success the clipboard owns `global`.
        }
    }
    #endif

    #if !os(Windows)
    private static func copyViaProcess(candidates: [[String]], text: String) {
        guard let command = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0[0]) })
        else { return }

        let data = Data(text.utf8)
        // Off the main actor: a full pipe must never stall input handling.
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                pipe.fileHandleForWriting.write(data)
                try? pipe.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch {
                // Best effort — OSC 52 remains the fallback channel.
            }
        }
    }
    #endif
}

extension Character {
    /// Undo coalescing granularity: wide characters (CJK, emoji, full-width
    /// punctuation) undo one character at a time; narrow (Latin) text undoes
    /// one word at a time (split at spaces).
    var undoesPerCharacter: Bool { width > 1 }
}

extension KeyEvent {
    /// Matches Ctrl+<letter> in both encodings: modifier-reported
    /// (e.g. "x" + `.ctrl`) and the legacy control byte (e.g. `\u{18}`).
    func isControl(_ letter: Character, raw: Character) -> Bool {
        if character == raw { return true }
        guard modifiers.contains(.ctrl), let character else { return false }
        return String(character).lowercased() == String(letter)
    }
}
