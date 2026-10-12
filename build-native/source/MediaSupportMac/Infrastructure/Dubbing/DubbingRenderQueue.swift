import Foundation

/// Shared budget across nested batches. Input/receipt keys serialize overlapping remote work.
@MainActor
final class DubbingWorkLimiter {
    private let limit: Int
    private var leases: [UUID: Set<String>] = [:]

    init(limit: Int = 2) { self.limit = max(1, min(2, limit)) }

    func acquire(keys: Set<String> = []) async throws -> UUID {
        while leases.count >= limit || leases.values.contains(where: { !$0.isDisjoint(with: keys) }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(30))
        }
        try Task.checkCancellation()
        let token = UUID()
        leases[token] = keys
        return token
    }

    func release(_ token: UUID) { leases.removeValue(forKey: token) }
}

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
