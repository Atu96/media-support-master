import Foundation

/// Bounded structured tasks: cancellation/error drains workers before returning.
@MainActor
enum DubbingRenderQueue {
    static func run(
        count: Int,
        limit: Int = 2,
        operation: @escaping @MainActor @Sendable (Int) async throws -> Void,
        completed: @escaping @MainActor @Sendable (Int) -> Void = { _ in }
    ) async throws {
        guard count > 0 else { return }
        try await withThrowingTaskGroup(of: Int.self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                group.addTask {
                    try Task.checkCancellation()
                    try await operation(index)
                    try Task.checkCancellation()
                    return index
                }
            }
            for _ in 0..<min(count, max(1, min(2, limit))) { enqueue(next); next += 1 }
            while let index = try await group.next() {
                try Task.checkCancellation()
                completed(index)
                if next < count { enqueue(next); next += 1 }
            }
        }
    }
}
