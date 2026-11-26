import Foundation

/// One explicit owner for a detached, cancellable I/O/encoding job. Callers still
/// validate request identity before applying results. Blocking Foundation calls
/// cannot be forcibly cancelled; operations must check cancellation at boundaries.
enum BackgroundWork {
    static func run<T: Sendable>(priority: TaskPriority = .userInitiated,
                                _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try work()
        }
        return try await value(of: task)
    }

    static func run<T: Sendable>(priority: TaskPriority = .userInitiated,
                                _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try await work()
        }
        return try await value(of: task)
    }

    private static func value<T: Sendable>(of worker: Task<T, Error>) async throws -> T {
        let result = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                          onCancel: { worker.cancel() })
        // A synchronous call may finish after cancellation without throwing.
        // Never publish that result as a successful current operation.
        try Task.checkCancellation()
        return result
    }
}
