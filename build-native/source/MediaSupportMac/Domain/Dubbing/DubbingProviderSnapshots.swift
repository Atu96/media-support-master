import Foundation

struct ElevenLabsQuotaSnapshot: Codable, Equatable, Sendable {
    let usedCharacters: Int
    let characterLimit: Int
    let nextReset: Date?
    let tier: String
    let updatedAt: Date

    var remainingCharacters: Int { max(0, characterLimit - usedCharacters) }
    var fractionUsed: Double {
        guard characterLimit > 0 else { return 0 }
        return min(1, max(0, Double(usedCharacters) / Double(characterLimit)))
    }
}

struct MaziaoAccountSnapshot: Codable, Equatable, Sendable {
    let remainingCredits: Int
    let updatedAt: Date
}
