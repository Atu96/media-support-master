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

struct GroqRateLimitSnapshot: Codable, Equatable, Sendable {
    let modelID: String?
    let requestLimit: Int?
    let remainingRequests: Int?
    let tokenLimit: Int?
    let remainingTokens: Int?
    let requestReset: String?
    let tokenReset: String?
    let updatedAt: Date

    var hasValues: Bool {
        requestLimit != nil || remainingRequests != nil || tokenLimit != nil || remainingTokens != nil
    }
}

struct GroqConnectionSnapshot: Codable, Equatable, Sendable {
    let availableModelCount: Int
    let verifiedAt: Date
}

struct GoogleLocalUsageSnapshot: Equatable, Sendable {
    let monthIdentifier: String
    let charactersSent: Int
}

enum ProviderUsageStore {
    private static let defaults = UserDefaults.standard
    private static let lock = NSLock()
    private static let elevenKey = "msm.usage.elevenLabs.snapshot"
    private static let maziaoKey = "msm.usage.maziao.snapshot"
    private static let groqKey = "msm.usage.groq.snapshot"
    private static let groqConnectionKey = "msm.usage.groq.connection"
    private static let googleMonthKey = "msm.usage.googleTTS.month"
    private static let googleCharactersKey = "msm.usage.googleTTS.characters"

    static func elevenLabsSnapshot() -> ElevenLabsQuotaSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return decode(ElevenLabsQuotaSnapshot.self, key: elevenKey)
    }

    static func saveElevenLabs(_ snapshot: ElevenLabsQuotaSnapshot) {
        lock.lock(); defer { lock.unlock() }
        encode(snapshot, key: elevenKey)
    }

    static func clearElevenLabs() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: elevenKey)
    }

    static func maziaoSnapshot() -> MaziaoAccountSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return decode(MaziaoAccountSnapshot.self, key: maziaoKey)
    }

    static func saveMaziao(_ snapshot: MaziaoAccountSnapshot) {
        lock.lock(); defer { lock.unlock() }
        encode(snapshot, key: maziaoKey)
    }

    static func clearMaziao() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: maziaoKey)
    }

    static func groqSnapshot() -> GroqRateLimitSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return decode(GroqRateLimitSnapshot.self, key: groqKey)
    }

    static func captureGroqHeaders(_ response: HTTPURLResponse) {
        guard let snapshot = groqSnapshot(from: response) else { return }
        saveGroq(snapshot)
    }

    static func captureGroqHeaders(_ response: HTTPURLResponse, modelID: String) {
        guard let snapshot = groqSnapshot(from: response, modelID: modelID) else { return }
        saveGroq(snapshot)
    }

    static func groqSnapshot(
        from response: HTTPURLResponse,
        modelID: String? = nil,
        updatedAt: Date = Date()
    ) -> GroqRateLimitSnapshot? {
        var headers: [String: String] = [:]
        for name in GroqRateLimitHeaderDecoder.names {
            headers[name] = response.value(forHTTPHeaderField: name)
        }
        guard let values = GroqRateLimitHeaderDecoder.decode(headers) else { return nil }
        return GroqRateLimitSnapshot(
            modelID: modelID,
            requestLimit: values.requestLimit,
            remainingRequests: values.remainingRequests,
            tokenLimit: values.tokenLimit,
            remainingTokens: values.remainingTokens,
            requestReset: values.requestReset,
            tokenReset: values.tokenReset,
            updatedAt: updatedAt
        )
    }

    static func saveGroq(_ snapshot: GroqRateLimitSnapshot) {
        lock.lock(); defer { lock.unlock() }
        encode(snapshot, key: groqKey)
    }

    static func clearGroq() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: groqKey)
    }

    static func groqConnectionSnapshot() -> GroqConnectionSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return decode(GroqConnectionSnapshot.self, key: groqConnectionKey)
    }

    static func saveGroqConnection(_ snapshot: GroqConnectionSnapshot) {
        lock.lock(); defer { lock.unlock() }
        encode(snapshot, key: groqConnectionKey)
    }

    static func clearGroqConnection() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: groqConnectionKey)
    }

    static func googleLocalUsage(now: Date = Date()) -> GoogleLocalUsageSnapshot {
        lock.lock(); defer { lock.unlock() }
        let month = monthIdentifier(for: now)
        resetGoogleMonthIfNeeded(month)
        return GoogleLocalUsageSnapshot(
            monthIdentifier: month,
            charactersSent: max(0, defaults.integer(forKey: googleCharactersKey))
        )
    }

    static func recordGoogleCharacters(_ text: String, now: Date = Date()) {
        let count = text.count
        guard count > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let month = monthIdentifier(for: now)
        resetGoogleMonthIfNeeded(month)
        let current = max(0, defaults.integer(forKey: googleCharactersKey))
        defaults.set(current + count, forKey: googleCharactersKey)
    }

    private static func resetGoogleMonthIfNeeded(_ month: String) {
        guard defaults.string(forKey: googleMonthKey) != month else { return }
        defaults.set(month, forKey: googleMonthKey)
        defaults.set(0, forKey: googleCharactersKey)
    }

    private static func monthIdentifier(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

enum ElevenLabsQuotaService {
    private struct SubscriptionResponse: Decodable {
        let tier: String?
        let characterCount: Int
        let characterLimit: Int
        let nextCharacterCountResetUnix: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case tier
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }

    static func refresh() async throws -> ElevenLabsQuotaSnapshot {
        let key = await DubbingCredentialAccess.shared.loadElevenLabs()
        guard !key.isEmpty else { throw DubbingError.missingCredential("ElevenLabs") }
        guard let endpoint = URL(string: "https://api.elevenlabs.io/v1/user/subscription") else {
            throw DubbingError.providerResponse("ElevenLabs quota endpoint không hợp lệ.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DubbingError.providerResponse("Không đọc được hạn mức ElevenLabs.")
        }
        let decoded = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
        let snapshot = ElevenLabsQuotaSnapshot(
            usedCharacters: max(0, decoded.characterCount),
            characterLimit: max(0, decoded.characterLimit),
            nextReset: decoded.nextCharacterCountResetUnix.map { Date(timeIntervalSince1970: $0) },
            tier: decoded.tier ?? "—",
            updatedAt: Date()
        )
        ProviderUsageStore.saveElevenLabs(snapshot)
        return snapshot
    }
}
