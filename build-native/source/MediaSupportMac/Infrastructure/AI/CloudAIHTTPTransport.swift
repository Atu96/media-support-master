import Foundation

enum CloudAIHTTPTransport {
    static func perform(
        _ request: URLRequest,
        fallbackMessage: String = "Nhà cung cấp AI từ chối yêu cầu.",
        groqRateLimitRetry: Bool = false,
        responseObserver: ((HTTPURLResponse) -> Void)? = nil
    ) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        responseObserver?(http)
        guard (200...299).contains(http.statusCode) else {
            if groqRateLimitRetry, http.statusCode == 429 {
                throw CloudAIError.rateLimited(
                    retryAfterSeconds: GroqRateLimitRetryPolicy.retryAfterSeconds(
                        http.value(forHTTPHeaderField: "retry-after")
                    )
                )
            }
            throw CloudAIError.http(
                status: http.statusCode,
                message: apiErrorMessage(from: data, fallback: fallbackMessage)
            )
        }
        return data
    }

    private static func apiErrorMessage(from data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return fallback
        }
        // Only preserve a known safe schema code, never failed_generation payloads.
        if error["code"] as? String == "json_validate_failed" {
            return "json_validate_failed: \(message)"
        }
        return message
    }
}
