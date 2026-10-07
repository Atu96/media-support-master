import Foundation

struct GroqRateLimitHeaderValues: Equatable, Sendable {
    let requestLimit: Int?
    let remainingRequests: Int?
    let tokenLimit: Int?
    let remainingTokens: Int?
    let requestReset: String?
    let tokenReset: String?
}

enum GroqRateLimitHeaderDecoder {
    static let names = [
        "x-ratelimit-limit-requests",
        "x-ratelimit-remaining-requests",
        "x-ratelimit-limit-tokens",
        "x-ratelimit-remaining-tokens",
        "x-ratelimit-reset-requests",
        "x-ratelimit-reset-tokens"
    ]

    static func decode(_ headers: [String: String]) -> GroqRateLimitHeaderValues? {
        var normalized: [String: String] = [:]
        for (name, value) in headers {
            normalized[name.lowercased()] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func integer(_ name: String) -> Int? { normalized[name].flatMap(Int.init) }

        let values = GroqRateLimitHeaderValues(
            requestLimit: integer("x-ratelimit-limit-requests"),
            remainingRequests: integer("x-ratelimit-remaining-requests"),
            tokenLimit: integer("x-ratelimit-limit-tokens"),
            remainingTokens: integer("x-ratelimit-remaining-tokens"),
            requestReset: normalized["x-ratelimit-reset-requests"],
            tokenReset: normalized["x-ratelimit-reset-tokens"]
        )
        let hasNumericValue = values.requestLimit != nil
            || values.remainingRequests != nil
            || values.tokenLimit != nil
            || values.remainingTokens != nil
        return hasNumericValue ? values : nil
    }
}
