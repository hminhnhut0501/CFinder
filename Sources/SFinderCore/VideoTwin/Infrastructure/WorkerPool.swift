import Foundation

/// Cancellation-aware permits; a released permit is handed directly to a waiter.
public actor WorkerPool {
    private let maxConcurrency: Int
    private var activeTasks = 0
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    public init(maxConcurrency: Int) { self.maxConcurrency = max(1, maxConcurrency) }

    public func withWorker<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await work()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if activeTasks < maxConcurrency { activeTasks += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaiter(id) } }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty { activeTasks -= 1 }
        else { waiters.removeFirst().1.resume() }
    }
}
