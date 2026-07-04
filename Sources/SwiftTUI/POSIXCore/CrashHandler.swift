#if os(macOS) || os(Linux)
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

private func crashHandler(signal: CInt) {
    let resetSequence = "\u{1b}[?1049l\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1015l\u{1b}[?1006l\u{1b}[?25h\u{1b}[0m\r\n"
    resetSequence.withCString { ptr in
        _ = write(STDOUT_FILENO, ptr, strlen(ptr))
    }
    // Remove handler and raise again
    var action = sigaction()
    #if os(Linux)
    #if canImport(Glibc)
    action.__sigaction_handler.sa_handler = { _ in exit(1) }
    #else
    action.__sa_handler.sa_handler = { _ in exit(1) }
    #endif
    #else
    action.__sigaction_u.__sa_handler = { _ in exit(1) }
    #endif
    sigemptyset(&action.sa_mask)
    action.sa_flags = 0
    sigaction(signal, &action, nil)
    raise(signal)
}

public func installCrashHandler() {
    var action = sigaction()
    #if os(Linux)
    #if canImport(Glibc)
    action.__sigaction_handler.sa_handler = crashHandler
    #else
    action.__sa_handler.sa_handler = crashHandler
    #endif
    #else
    action.__sigaction_u.__sa_handler = crashHandler
    #endif
    sigemptyset(&action.sa_mask)
    action.sa_flags = SA_RESTART

    sigaction(SIGILL, &action, nil)
    sigaction(SIGABRT, &action, nil)
    sigaction(SIGBUS, &action, nil)
    sigaction(SIGSEGV, &action, nil)
    sigaction(SIGQUIT, &action, nil)
}
#endif
