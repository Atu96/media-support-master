import Foundation

enum GroqRateLimitRetryPolicy {
    static let maxRetries = 2
    static let maxWaitSeconds = 75.0

    static func retryAfterSeconds(_ raw: String?) -> Double? {
        guard let raw,
              let seconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return min(seconds, 86_400)
    }

    static func waitSeconds(retryAfter: Double?, retryIndex: Int) -> Double? {
        guard retryIndex < maxRetries else { return nil }
        let seconds = retryAfter ?? Double(6 * (retryIndex + 1))
        guard seconds.isFinite, seconds <= maxWaitSeconds else { return nil }
        return min(maxWaitSeconds, max(1, seconds + 0.5))
    }

    static func run<T>(
        progress: (@Sendable (String) -> Void)?,
        sleep: (Double) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        operation: (Int) async throws -> T
    ) async throws -> T {
        for attempt in 0...maxRetries {
            try Task.checkCancellation()
            do {
                return try await operation(attempt)
            } catch let error as CloudAIError {
                guard case let .rateLimited(retryAfter) = error,
                      let seconds = waitSeconds(retryAfter: retryAfter, retryIndex: attempt)
                else { throw error }
                progress?("⏳ Groq giới hạn tốc độ · chờ \(Int(ceil(seconds))) giây · thử lại \(attempt + 1)/\(maxRetries)")
                try await sleep(seconds)
            }
        }
        throw CloudAIError.rateLimited(retryAfterSeconds: nil)
    }
}
