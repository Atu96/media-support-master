import Foundation

/// Owns the disk cache and its independent load/merge/usage task lifecycles.
/// Session retains cue reconciliation and observable editor state.
@MainActor
final class DubbingCacheCoordinator {
    let store: DubbingCacheStore
    let load = DubbingJobLifecycle()
    let merge = DubbingJobLifecycle()
    let usage = DubbingJobLifecycle()

    init(store: DubbingCacheStore) { self.store = store }

    func cancelAll() { load.cancel(); merge.cancel(); usage.cancel() }

    func refreshUsage(publish: @escaping (DubbingCacheUsage) -> Void) {
        let token = usage.begin()
        let store = self.store
        usage.task = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return DubbingCacheUsage.empty }
                return (try? store.usage()) ?? .empty
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, self.usage.generation == token, !Task.isCancelled else { return }
            publish(result)
            self.usage.finish(token)
        }
    }
}
