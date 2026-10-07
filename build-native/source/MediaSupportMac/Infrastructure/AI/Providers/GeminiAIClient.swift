import Foundation

struct GeminiAIClient: CloudAIClient {
    static let model = "gemini-3.6-flash"

    func generate(_ generation: CloudAIGenerationRequest) async throws -> String {
        let key = GeminiCredentialStore.load()
        guard !key.isEmpty else {
            throw CloudAIError.missingKey(provider: "Gemini")
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent"
        guard let url = URL(string: endpoint) else {
            throw CloudAIError.invalidEndpoint
        }

        var generationConfig: [String: Any] = [:]
        if let maxOutputTokens = generation.maxOutputTokens {
            generationConfig["maxOutputTokens"] = maxOutputTokens
        }
        if generation.expectsJSON {
            generationConfig["responseMimeType"] = "application/json"
        }

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": generation.system]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": generation.user]]
                ]
            ],
            "generationConfig": generationConfig
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await CloudAIHTTPTransport.perform(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = response.candidates
            .first?
            .content
            .parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            throw CloudAIError.invalidResponse
        }
        return text
    }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]
        }

        let content: Content
    }

    let candidates: [Candidate]
}
