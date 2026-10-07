import Foundation

/// Sanitized transport contract. No credentials, request text or provider payload
/// is included in errors; fixtures can exercise this without network access.
enum GroqResponsePolicy {
    static func decode(_ data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first else { throw CloudAIError.invalidResponse }
        if choice.finish_reason == "length" { throw CloudAIError.truncatedResponse }
        guard choice.finish_reason == nil || choice.finish_reason == "stop",
              let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw CloudAIError.invalidResponse }
        return text
    }

    static func shouldRetryWithoutStructuredJSON(_ error: CloudAIError) -> Bool {
        guard case let .http(status, message) = error, status == 400 else { return false }
        let normalized = message.lowercased()
        return normalized.contains("failed_generation")
            || normalized.contains("json_validate_failed")
            || normalized.contains("failed to validate json")
            || normalized.contains("json mode")
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }
}
