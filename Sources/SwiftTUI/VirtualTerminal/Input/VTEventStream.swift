// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

/// An asynchronous stream of terminal input events.
///
/// `VTEventStream` provides an efficient way to consume terminal input events
/// using Swift's async/await concurrency model. The stream automatically
/// handles the complexities of terminal input processing, delivering a clean
/// sequence of `VTEvent` values that your application can process.
///
/// The stream intelligently batches events from the underlying terminal APIs
/// for optimal performance while providing a simple single-event interface
/// to your application code.
///
/// ## Usage Example
/// ```swift
/// for try await event in eventStream {
///   switch event {
///   case .key(let key):
///     if key.character == "q" {
///       break  // Exit event loop
///     }
///     handleKeyInput(key)
///   case .mouse(let mouse):
///     handleMouseInput(mouse)
///   case .resize(let resize):
///     handleTerminalResize(resize)
///   }
/// }
/// ```
///
/// ## Error Handling
/// The stream can throw errors if the underlying terminal input fails.
/// Handle errors appropriately in your event processing loop:
///
/// ```swift
/// do {
///   for try await event in eventStream {
///     processEvent(event)
///   }
/// } catch {
///   handleInputError(error)
/// }
/// ```
public struct VTEventStream: AsyncSequence, Sendable {
  public typealias Element = VTEvent
  private let stream: AsyncThrowingStream<[VTEvent], Error>

  internal init(_ stream: AsyncThrowingStream<[VTEvent], Error>) {
    self.stream = stream
  }

  /// An iterator that flattens batched events into individual events.
  ///
  /// This iterator efficiently manages internal buffering to provide smooth
  /// single-event consumption while preserving the performance benefits
  /// of batch reading from the underlying terminal APIs.
  ///
  /// The iterator automatically handles the complexity of buffering and
  /// flattening batched events, so your application code can focus on
  /// processing individual events without worrying about batching details.
  ///
  /// ## Performance Characteristics
  ///
  /// The iterator maintains an internal buffer to minimize the number of
  /// async operations while ensuring events are delivered as quickly as
  /// possible. This design provides:
  /// - Low latency for interactive applications
  /// - High throughput for batch operations
  /// - Efficient memory usage through buffer reuse
  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: AsyncThrowingStream<[VTEvent], Error>.Iterator
    private var buffer: [VTEvent] = []
    private var offset: Int = 0

    internal init(underlying: AsyncThrowingStream<[VTEvent], Error>.Iterator) {
      self.iterator = underlying
    }

    public mutating func next() async throws -> Element? {
      while true {
        if offset < buffer.count {
          let event = buffer[offset]
          offset += 1
          return event
        }

        guard let batch = try await iterator.next() else {
          return nil
        }
        buffer = VTEvent.coalescingMouseMoves(batch)
        offset = 0
        // Empty after coalesce (should be rare) — fetch again.
      }
    }
  }

  /// Creates an async iterator for processing events from the stream.
  ///
  /// This method is called automatically when you use `for try await` loops
  /// or other async sequence operations. The returned iterator handles all
  /// the complexity of buffering and flattening batched events.
  ///
  /// You typically won't call this method directly, but instead use it
  /// implicitly through async sequence operations:
  ///
  /// ```swift
  /// // This automatically calls makeAsyncIterator()
  /// for try await event in eventStream {
  ///   processEvent(event)
  /// }
  /// ```
  ///
  /// - Returns: A new async iterator for consuming events from this stream.
  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(underlying: stream.makeAsyncIterator())
  }
}
