import Foundation

struct GroqConnectionVerification: Equatable, Sendable {
    let availableModelCount: Int
    let usageSnapshot: GroqRateLimitSnapshot?
}

enum GroqConnectionVerifier {
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/models")!

    static func verify(apiKey: String) async throws -> GroqConnectionVerification {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CloudAIError.missingKey(provider: "Groq")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
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

        return GroqConnectionVerification(
            availableModelCount: try GroqConnectionResponseDecoder.modelCount(from: data),
            usageSnapshot: ProviderUsageStore.groqSnapshot(from: http)
        )
    }
}

enum GroqConnectionVerificationError: LocalizedError, Equatable {
    case rejectedKey
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .rejectedKey:
            "Groq từ chối API key này. Hãy kiểm tra lại key mới."
        case let .http(status):
            "Không xác thực được API key Groq (HTTP \(status))."
        }
    }
}
