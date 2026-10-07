import Foundation

/// Một owner cho các lần đổi bố cục: debounce trên UI, Core Text trên worker,
/// chỉ trả kết quả của yêu cầu cuối. Hủy worker hợp tác để không chất đống CPU.
@MainActor
final class SubtitleLayoutReflowController {
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let debounceNanoseconds: UInt64
    private let onStateChange: (Bool) -> Void
    private(set) var isRunning = false {
        didSet { if oldValue != isRunning { onStateChange(isRunning) } }
    }

    init(debounceNanoseconds: UInt64 = 150_000_000, onStateChange: @escaping (Bool) -> Void = { _ in }) {
        self.debounceNanoseconds = debounceNanoseconds
        self.onStateChange = onStateChange
    }

    func schedule(
        operation: @escaping @Sendable () -> [SRTSegment],
        completion: @escaping @MainActor ([SRTSegment]) -> Void
    ) {
        task?.cancel()
        let requestID = UUID()
        generation = requestID
        isRunning = true
        task = Task { [weak self, debounceNanoseconds] in
            do { try await Task.sleep(nanoseconds: debounceNanoseconds) }
            catch { return }
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return [SRTSegment]() }
                return operation()
            }
            let updated = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.generation == requestID else { return }
            self.task = nil
            self.isRunning = false
            guard !Task.isCancelled else { return }
            completion(updated)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation = UUID()
        isRunning = false
    }

    deinit { task?.cancel() }
}
