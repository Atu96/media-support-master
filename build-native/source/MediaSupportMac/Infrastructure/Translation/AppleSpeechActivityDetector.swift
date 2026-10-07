import CoreMedia
import Foundation
import SoundAnalysis

/// VAD native dùng classifier tích hợp của Apple. Chạy một lần trong job Chép lời;
/// không chạy khi scroll/zoom/skim và không suy speech từ biên độ waveform.
enum AppleSpeechActivityDetector {
    private static let confidenceThreshold = 0.50

    static func detect(in audioURL: URL) async throws -> [SpeechActivityInterval] {
        let analyzer = try SNAudioFileAnalyzer(url: audioURL)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        guard request.knownClassifications.contains("speech") else { return [] }

        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
        request.overlapFactor = 0.5

        let observer = SpeechActivityObserver(confidenceThreshold: confidenceThreshold)
        try analyzer.add(request, withObserver: observer)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[SpeechActivityInterval], Error>) in
                analyzer.analyze { reachedEnd in
                    do {
                        if let failure = observer.failure {
                            throw failure
                        }
                        guard reachedEnd else { throw CancellationError() }
                        continuation.resume(returning: observer.intervals)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            analyzer.cancelAnalysis()
        }
    }
}

private final class SpeechActivityObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private let confidenceThreshold: Double
    private var storedIntervals: [SpeechActivityInterval] = []
    private var storedFailure: Error?

    init(confidenceThreshold: Double) {
        self.confidenceThreshold = confidenceThreshold
    }

    var intervals: [SpeechActivityInterval] {
        lock.lock()
        defer { lock.unlock() }
        return storedIntervals
    }

    var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedFailure
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult,
              let speech = result.classification(forIdentifier: "speech"),
              speech.confidence >= confidenceThreshold
        else { return }

        let windowStart = result.timeRange.start.seconds
        let windowDuration = result.timeRange.duration.seconds
        guard windowStart.isFinite, windowDuration.isFinite, windowDuration > 0 else { return }

        // Với overlap 50%, chỉ lấy nửa giữa của cửa sổ để mép speech không bị
        // nở thêm 0,25 giây ở cả hai đầu; refiner sẽ thêm padding nhỏ có kiểm soát.
        let inset = windowDuration * 0.25
        let interval = SpeechActivityInterval(
            startSeconds: max(0, windowStart + inset),
            endSeconds: max(0, windowStart + windowDuration - inset),
            confidence: speech.confidence
        )
        lock.lock()
        storedIntervals.append(interval)
        lock.unlock()
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {
        lock.lock()
        storedFailure = error
        lock.unlock()
    }
}
