import Foundation

/// Serializes model preparation across suspension points, not just actor entry.
/// Separate recognizers retain independent decoder state but never write the cache concurrently.
actor MeetingModelPreparationQueue {
    static let shared = MeetingModelPreparationQueue()
    private var tail: Task<Void, Error>?
    private var tailID: UUID?

    func run(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let previous = self.tail
        let id = UUID()
        let task = Task {
            _ = await previous?.result
            try Task.checkCancellation()
            try await operation()
        }
        self.tail = task
        self.tailID = id
        defer {
            if self.tailID == id {
                self.tail = nil
                self.tailID = nil
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: {
            task.cancel()
        }
    }
}
