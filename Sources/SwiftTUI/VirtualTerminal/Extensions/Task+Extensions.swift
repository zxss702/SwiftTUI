// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

import Dispatch

final class Box<T>: @unchecked Sendable {
    var value: T!
}

extension Task where Failure == Error {
  @discardableResult
  package static func synchronously(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Success) throws(Failure) -> Success {
    let box = Box<Result<Success, Failure>>()

    let semaphore = DispatchSemaphore(value: 0)
    _ = Task<Void, Failure>(priority: priority) {
      // This task will run the operation and capture the result.
      // It will signal the semaphore when done.
      defer { semaphore.signal() }

      do {
        box.value = try await Result<Success, Failure>.success(operation())
      } catch {
        box.value = Result<Success, Failure>.failure(error)
      }
    }
    semaphore.wait()

    return try box.value.get()
  }
}

extension Task where Failure == Never {
  @discardableResult
  package static func synchronously(priority: TaskPriority? = nil, operation: @escaping @Sendable () async -> Success) -> Success {
    let box = Box<Success>()

    let semaphore = DispatchSemaphore(value: 0)
    _ = Task<Void, Never>(priority: priority) {
      defer { semaphore.signal() }
      box.value = await operation()
    }
    semaphore.wait()

    return box.value
  }
}

internal struct TimeoutError: Error, CustomStringConvertible {
  public var description: String { "The operation timed out." }
}

extension Task {
  internal static func withTimeout(timeout: Duration,
                                   priority: TaskPriority? = nil,
                                   operation: @escaping @Sendable () async throws -> Success) async throws -> Success {
    return try await withThrowingTaskGroup(of: Success.self) { group in
      defer { group.cancelAll() }

      group.addTask(priority: priority) {
        try await operation()
      }

      group.addTask {
        // Wait for the specified timeout
        try await Task<Never, Never>.sleep(for: timeout)
        throw TimeoutError()
      }

      guard let result = try await group.next() else {
        throw TimeoutError()
      }

      return result
    }
  }
}
