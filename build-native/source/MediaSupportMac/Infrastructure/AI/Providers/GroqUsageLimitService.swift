import Foundation

enum GroqUsageLimitService {
    private static let endpoint = URL(
        string: "https://api.groq.com/openai/v1/chat/completions"
    )!

    static func refresh(apiKey: String, model: GroqTextModel) async throws -> GroqRateLimitSnapshot {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CloudAIError.missingKey(provider: "Groq")
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": [["role": "user", "content": "."]],
            "max_completion_tokens": 1
        ]
        if model == .qwenAsian {
            body["reasoning_effort"] = "none"
        } else {
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = false
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403:
                throw GroqConnectionVerificationError.rejectedKey
            default:
                throw GroqConnectionVerificationError.http(http.statusCode)
            }
        }
        guard let snapshot = ProviderUsageStore.groqSnapshot(
            from: http,
            modelID: model.rawValue
        ) else {
            throw GroqUsageLimitError.missingHeaders
        }
        ProviderUsageStore.saveGroq(snapshot)
        return snapshot
    }
}

enum GroqUsageLimitError: LocalizedError {
    case missingHeaders

    var errorDescription: String? {
        "Groq đã phản hồi nhưng không gửi dữ liệu hạn mức."
    }
}
