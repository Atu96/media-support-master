import Foundation

/// Owns one metadata request. Invalidated work cannot publish success, error or
/// loading state even if its client ignores cancellation.
@MainActor
final class DubbingRefreshCoordinator<Value> {
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var loading: ((Bool) -> Void)?

    func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
        loading?(false)
        loading = nil
    }

    func run(operation: @escaping @MainActor () async throws -> Value,
             loading: @escaping (Bool) -> Void,
             publish: @escaping (Value) -> Void,
             failure: @escaping (Error) -> Void) async {
        if let task { await task.value; return }
        let token = UUID()
        generation = token
        self.loading = loading
        loading(true)
        let task = Task { [weak self] in
            do {
                let value = try await operation()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                publish(value)
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if !(error is CancellationError) { failure(error) }
            }
            guard let self, self.generation == token else { return }
            self.task = nil
            self.loading = nil
            loading(false)
        }
        self.task = task
        await task.value
    }

    deinit { task?.cancel() }
}
