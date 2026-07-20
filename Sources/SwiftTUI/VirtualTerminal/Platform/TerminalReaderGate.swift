import Synchronization

/// Process-wide terminal input ownership. A prior session’s blocking read
/// loop must not stay attached after the next `Application.start()` claims
/// the TTY / console — otherwise History→Chat (and similar) sessions steal
/// every-other press/key from the live pump.
enum StdinReaderGate {
  private static let generation = Mutex<UInt64>(0)

  /// Invalidate any prior reader; return this session’s generation.
  static func claim() -> UInt64 {
    generation.withLock { value in
      value &+= 1
      return value
    }
  }

  static func owns(_ gen: UInt64) -> Bool {
    generation.withLock { $0 == gen }
  }
}
