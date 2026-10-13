import Foundation

/// Each slot owns cancellation and generation independently. Finishing an old
/// job must never clear a newer job's handle.
@MainActor
final class DubbingJobLifecycle {
    var task: Task<Void, Never>?
    private(set) var generation: UUID?

    func begin() -> UUID {
        cancel()
        let token = UUID()
        generation = token
        return token
    }

    func finish(_ token: UUID) {
        guard generation == token else { return }
        task = nil
        generation = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation = nil
    }

    deinit { task?.cancel() }
}
