import Foundation

struct GroqAIClient: CloudAIClient {
    private static let endpoint = URL(
        string: "https://api.groq.com/openai/v1/chat/completions"
    )!

    func generate(_ generation: CloudAIGenerationRequest) async throws -> String {
        let key = GroqCredentialStore.load()
        guard !key.isEmpty else {
            throw CloudAIError.missingKey(provider: "Groq")
        }

        let selectedModel = GroqModelPreferences.selectedTextModel
        return try await GroqRateLimitRetryPolicy.run(progress: generation.progress) { _ in
            do {
                return try await performGeneration(
                    generation,
                    key: key,
                    model: selectedModel,
                    usesStructuredJSON: generation.expectsJSON
                )
            } catch let error as CloudAIError where generation.expectsJSON && GroqResponsePolicy.shouldRetryWithoutStructuredJSON(error) {
                // JSON-mode 400 được thử lại đúng một lần không response_format.
                return try await performGeneration(
                    generation,
                    key: key,
                    model: selectedModel,
                    usesStructuredJSON: false
                )
            }
        }
    }

    private func performGeneration(
        _ generation: CloudAIGenerationRequest,
        key: String,
        model: GroqTextModel,
        usesStructuredJSON: Bool
    ) async throws -> String {
        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": generation.system],
                ["role": "user", "content": generation.user]
            ]
        ]
        if let maxOutputTokens = generation.maxOutputTokens {
            body["max_completion_tokens"] = maxOutputTokens
        }
        if model == .qwenAsian {
            // Qwen dịch ở non-thinking mode để chỉ trả nội dung, không lẫn suy luận vào subtitle.
            body["reasoning_effort"] = "none"
        } else {
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = false
        }
        if usesStructuredJSON {
            body["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await CloudAIHTTPTransport.perform(
            request,
            groqRateLimitRetry: true,
            responseObserver: { response in
                ProviderUsageStore.captureGroqHeaders(response, modelID: model.rawValue)
            }
        )
        return try GroqResponsePolicy.decode(data)
    }
}
