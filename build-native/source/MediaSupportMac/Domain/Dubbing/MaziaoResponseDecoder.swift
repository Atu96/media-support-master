import Foundation

struct MaziaoSubmitReceipt: Equatable, Sendable {
    let taskID: String
    let remainingCredits: Int?
}

struct MaziaoTaskState: Equatable, Sendable {
    let id: String
    let status: String
    let resultURL: URL?
    let resultURLs: [URL]
}

/// Fixed operation labels only: never include a voice/task ID or a signed URL.
enum MaziaoAPIOperation: String {
    case account = "auth/me"
    case voices = "voices"
    case voice = "voice detail"
    case submit = "tts/submit"
    case status = "tts/status"
    case previewAudio = "preview audio"
    case resultAudio = "result audio"
}

enum MaziaoTextError: LocalizedError {
    case tooShort, tooLong, incompatibleBatch, missingResults, invalidResultURL

    var errorDescription: String? {
        switch self {
        case .tooShort:
            L10n.string("Maziao yêu cầu tổng nội dung chưa tạo giọng vượt 100 ký tự. Hãy chọn thêm câu phụ đề; app không tự thêm hoặc lặp lời.")
        case .tooLong:
            L10n.string("Maziao chỉ nhận dưới 250000 ký tự mỗi lượt. Hãy chia nhỏ nội dung rồi thử lại.")
        case .incompatibleBatch:
            L10n.string("Các câu trong một lượt Maziao phải dùng cùng giọng, mô hình và tốc độ.")
        case .missingResults:
            L10n.string("Maziao trả thiếu hoặc thừa tệp âm thanh. App đã dừng để tránh gán nhầm giọng vào câu phụ đề.")
        case .invalidResultURL:
            L10n.string("Maziao trả đường dẫn âm thanh không hợp lệ.")
        }
    }
}

enum MaziaoTextPolicy {
    // Server error observed live: strictly greater than 100 and less than 250000.
    static let minimumExclusive = 100
    static let maximumExclusive = 250_000

    static func validate(_ texts: [String]) throws {
        guard !texts.isEmpty else { throw DubbingError.emptyText }
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.allSatisfy({ !$0.isEmpty }) else { throw DubbingError.emptyText }
        // Graphemes for the minimum and UTF-16 for the maximum are conservative
        // for both code-point and JS string length validation; payload stays intact.
        guard trimmed.reduce(0, { $0 + $1.count }) > minimumExclusive else { throw MaziaoTextError.tooShort }
        guard texts.reduce(max(0, texts.count - 1), { $0 + $1.utf16.count }) < maximumExclusive else {
            throw MaziaoTextError.tooLong
        }
    }

}

enum MaziaoBatchPlanner {
    static func batches(for requests: [DubbingSpeechRequest]) throws -> [[DubbingSpeechRequest]] {
        guard let first = requests.first else { return [] }
        guard Set(requests.map(\.cueID)).count == requests.count,
              requests.allSatisfy({ $0.provider == .maziao && $0.modelIdentifier == first.modelIdentifier
                && $0.voiceIdentifier == first.voiceIdentifier && $0.rate == first.rate
                && $0.localeIdentifier == first.localeIdentifier }) else { throw MaziaoTextError.incompatibleBatch }
        var batches: [[DubbingSpeechRequest]] = []
        var current: [DubbingSpeechRequest] = []
        var characters = 0
        var units = 0
        for request in requests {
            let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw DubbingError.emptyText }
            let size = request.text.utf16.count
            guard size < MaziaoTextPolicy.maximumExclusive else { throw MaziaoTextError.tooLong }
            if !current.isEmpty, units + size + 1 >= MaziaoTextPolicy.maximumExclusive {
                try MaziaoTextPolicy.validate(current.map(\.text))
                batches.append(current); current = []; characters = 0; units = 0
            }
            units += size + (current.isEmpty ? 0 : 1)
            current.append(request); characters += text.count
            if characters > 100, characters >= 4000 || current.count >= 32 {
                batches.append(current); current = []; characters = 0; units = 0
            }
        }
        if !current.isEmpty {
            if characters <= 100, let last = batches.popLast() {
                var previous = last
                let combined = previous + current
                if (try? MaziaoTextPolicy.validate(combined.map(\.text))) != nil {
                    current = combined
                } else {
                    // Move whole cues; never split or repeat a user's text.
                    while characters <= 100, previous.count > 1 {
                        let moved = previous.removeLast()
                        current.insert(moved, at: 0)
                        characters += moved.text.trimmingCharacters(in: .whitespacesAndNewlines).count
                    }
                    try MaziaoTextPolicy.validate(previous.map(\.text))
                    batches.append(previous)
                }
            }
            batches.append(current)
        }
        // Validate the whole plan before the first paid submit.
        for batch in batches { try MaziaoTextPolicy.validate(batch.map(\.text)) }
        return batches
    }
}

enum MaziaoPollingPolicy {
    static let minimumTimeoutSeconds: TimeInterval = 300
    static let maximumTimeoutSeconds: TimeInterval = 1_800
    static let maximumTransientStatusFailures = 3

    static func timeoutSeconds(characterCount: Int, partCount: Int) -> TimeInterval {
        let characters = max(0, characterCount)
        let parts = max(1, partCount)
        let estimate = 240 + Double(characters) * 0.25 + Double(parts) * 3
        return min(maximumTimeoutSeconds, max(minimumTimeoutSeconds, estimate))
    }

    static func pollIntervalSeconds(afterAttempt attempt: Int) -> TimeInterval {
        if attempt < 10 { return 1 }
        if attempt < 25 { return 2 }
        return 4
    }
}

/// Encodes the authenticated TTS schema from Maziao's full API documentation.
/// Keep this pure so a provider-side schema change fails an offline regression
/// before it reaches a paid API call.
enum MaziaoRequestEncoder {
    static func submitBody(
        text: String,
        voiceID: String,
        modelID: String,
        speed: Double
    ) throws -> Data {
        try MaziaoTextPolicy.validate([text])
        let payload: [String: Any] = [
            "mode": "paragraph",
            "parts": [[
                "text": text,
                "voiceId": voiceID,
                "startTime": 0,
            ]],
            "voiceId": voiceID,
            "previewText": String(text.prefix(120)),
            "config": [
                "speed": speed,
                "volume": 1.0,
                "pitch": 1.0,
                "export_srt": false,
            ],
            "modelId": modelID,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func batchBody(_ requests: [DubbingSpeechRequest]) throws -> Data {
        guard let first = requests.first else { throw DubbingError.emptyText }
        _ = try MaziaoBatchPlanner.batches(for: requests)
        try MaziaoTextPolicy.validate(requests.map(\.text))
        guard let voice = first.voiceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !voice.isEmpty else {
            throw DubbingError.missingVoiceIdentifier("Maziao")
        }
        let speed = min(1.5, max(0.5, Double(first.rate / 0.5)))
        let parts: [[String: Any]] = requests.map {
            ["text": $0.text, "voiceId": voice, "speed": speed, "pitch": 1.0]
        }
        return try JSONSerialization.data(withJSONObject: [
            "mode": "multiParts", "parts": parts, "modelId": first.modelIdentifier,
            "previewText": String(requests.map(\.text).joined(separator: "\n").prefix(120)),
            "config": ["volume": 1.0, "pitch": 1.0, "export_srt": false],
        ], options: [.sortedKeys])
    }

}

/// Decodes Maziao transport responses without touching Keychain or the network.
/// Keep this boundary pure so provider schema changes can be covered by fixtures.
enum MaziaoResponseDecoder {
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
    }

    private struct Account: Decodable {
        let credits: Int
    }

    private struct VoicePage: Decodable {
        let items: [Voice]
        let total: Int?
        let limit: Int?
        let offset: Int?
    }

    private struct Voice: Decodable {
        let id: String
        let name: String
        let language: String?
        let previewURL: URL?
        let gender: String?
        let modelID: String?

        enum CodingKeys: String, CodingKey {
            case id, name, language, gender
            case previewURL = "previewUrl"
            case previewURLSnake = "preview_url"
            case modelID = "modelId"
            case modelIDSnake = "model_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            language = try container.decodeIfPresent(String.self, forKey: .language)
            gender = try container.decodeIfPresent(String.self, forKey: .gender)
            modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
                ?? container.decodeIfPresent(String.self, forKey: .modelIDSnake)
            previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
                ?? container.decodeIfPresent(URL.self, forKey: .previewURLSnake)
        }

        var descriptor: MaziaoVoiceDescriptor {
            MaziaoVoiceDescriptor(
                id: id,
                name: name,
                language: language ?? "—",
                gender: gender ?? "—",
                previewURL: previewURL,
                modelID: modelID
            )
        }
    }

    private struct SubmitResult: Decodable {
        let taskID: String
        let remainingCredits: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case taskID = "taskId"
            case taskIDSnake = "task_id"
            case remainingCredits
            case remainingCreditsSnake = "remaining_credits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
                ?? container.decodeIfPresent(String.self, forKey: .taskIDSnake)
                ?? container.decode(String.self, forKey: .id)
            remainingCredits = try container.decodeIfPresent(Int.self, forKey: .remainingCredits)
                ?? container.decodeIfPresent(Int.self, forKey: .remainingCreditsSnake)
        }
    }

    private struct TaskStatus: Decodable {
        let id: String
        let status: String
        let resultURL: URL?
        let resultURLs: [URL]?

        enum CodingKeys: String, CodingKey {
            case id, status
            case taskID = "taskId"
            case taskIDSnake = "task_id"
            case resultURL = "resultUrl"
            case resultURLSnake = "result_url"
            case resultURLs = "resultUrls"
            case resultURLsSnake = "result_urls"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .taskID)
                ?? container.decode(String.self, forKey: .taskIDSnake)
            status = try container.decode(String.self, forKey: .status)
            let rawURL = try container.decodeIfPresent(String.self, forKey: .resultURL)
                ?? container.decodeIfPresent(String.self, forKey: .resultURLSnake)
            let encodedURLs = rawURL.flatMap { try? JSONDecoder().decode([URL].self, from: Data($0.utf8)) }
            resultURL = encodedURLs == nil ? rawURL.flatMap(URL.init(string:)) : nil
            resultURLs = try container.decodeIfPresent([URL].self, forKey: .resultURLs)
                ?? container.decodeIfPresent([URL].self, forKey: .resultURLsSnake)
                ?? encodedURLs
        }
    }

    static func voices(from data: Data) throws -> [MaziaoVoiceDescriptor] {
        try voicePage(from: data).voices
    }

    static func voicePage(from data: Data) throws -> MaziaoVoicePage {
        let page = try JSONDecoder()
            .decode(Envelope<VoicePage>.self, from: data)
            .data
        let decoded = page.items.map(\.descriptor)
        let discoveredURLs = previewURLsByVoiceID(from: data)
        let voices = decoded.map { voice in
            guard voice.previewURL == nil, let previewURL = discoveredURLs[voice.id] else { return voice }
            return MaziaoVoiceDescriptor(
                id: voice.id,
                name: voice.name,
                language: voice.language,
                gender: voice.gender,
                previewURL: previewURL,
                modelID: voice.modelID
            )
        }
        return MaziaoVoicePage(
            voices: voices,
            total: page.total,
            limit: page.limit,
            offset: page.offset
        )
    }

    static func voice(from data: Data) throws -> MaziaoVoiceDescriptor {
        let decoded = try JSONDecoder().decode(Envelope<Voice>.self, from: data).data.descriptor
        guard decoded.previewURL == nil,
              let previewURL = firstPreviewURL(in: envelopeDataObject(from: data)) else {
            return decoded
        }
        return MaziaoVoiceDescriptor(
            id: decoded.id,
            name: decoded.name,
            language: decoded.language,
            gender: decoded.gender,
            previewURL: previewURL,
            modelID: decoded.modelID
        )
    }

    static func remainingCredits(from data: Data) throws -> Int {
        max(0, try JSONDecoder().decode(Envelope<Account>.self, from: data).data.credits)
    }

    static func submitReceipt(from data: Data) throws -> MaziaoSubmitReceipt {
        let decoder = JSONDecoder()
        let result: SubmitResult
        if let envelope = try? decoder.decode(Envelope<SubmitResult>.self, from: data) {
            result = envelope.data
        } else {
            result = try decoder.decode(SubmitResult.self, from: data)
        }
        return MaziaoSubmitReceipt(
            taskID: result.taskID,
            remainingCredits: result.remainingCredits.map { max(0, $0) }
        )
    }

    static func taskStates(from data: Data) throws -> [MaziaoTaskState] {
        let decoder = JSONDecoder()
        let decoded: [TaskStatus]
        if let envelope = try? decoder.decode(Envelope<[TaskStatus]>.self, from: data) {
            decoded = envelope.data
        } else {
            decoded = try decoder.decode([TaskStatus].self, from: data)
        }
        return decoded.map {
            MaziaoTaskState(
                id: $0.id,
                status: $0.status,
                resultURL: $0.resultURL,
                resultURLs: $0.resultURLs ?? []
            )
        }
    }

    static func audioURLs(from state: MaziaoTaskState, expectedCount: Int) throws -> [URL] {
        let urls = state.resultURLs.isEmpty ? state.resultURL.map { [$0] } ?? [] : state.resultURLs
        guard expectedCount > 0, urls.count == expectedCount else { throw MaziaoTextError.missingResults }
        guard urls.allSatisfy({ $0.scheme?.lowercased() == "https" && $0.host != nil }) else {
            throw MaziaoTextError.invalidResultURL
        }
        return urls
    }

    static func providerErrorMessage(
        from data: Data,
        statusCode: Int?,
        operation: MaziaoAPIOperation? = nil
    ) -> String {
        var prefix = statusCode.map { "Maziao HTTP \($0)" } ?? "Maziao"
        if let operation { prefix += " [\(operation.rawValue)]" }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return prefix
        }
        let messages = providerMessages(in: object, depth: 0)
        guard !messages.isEmpty else { return prefix }
        return prefix + ": " + String(messages.joined(separator: " · ").prefix(1200))
    }

    private static func previewURLsByVoiceID(from data: Data) -> [String: URL] {
        guard let object = envelopeDataObject(from: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return [:] }
        return items.reduce(into: [:]) { result, item in
            guard let id = item["id"] as? String,
                  let previewURL = firstPreviewURL(in: item) else { return }
            result[id] = previewURL
        }
    }

    private static func envelopeDataObject(from data: Data) -> Any? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["data"]
    }

    private static func firstPreviewURL(in value: Any?) -> URL? {
        if let dictionary = value as? [String: Any] {
            for (key, candidate) in dictionary {
                let normalized = key.lowercased().filter(\.isLetter)
                let isPreview = normalized.contains("preview") || normalized.contains("sample")
                let isImage = normalized.contains("image")
                    || normalized.contains("avatar")
                    || normalized.contains("thumbnail")
                    || normalized.contains("photo")
                if isPreview, !isImage,
                   let string = candidate as? String,
                   let url = URL(string: string),
                   url.scheme?.lowercased() == "https" {
                    return url
                }
            }
            for candidate in dictionary.values {
                if let url = firstPreviewURL(in: candidate) { return url }
            }
        } else if let array = value as? [Any] {
            for candidate in array {
                if let url = firstPreviewURL(in: candidate) { return url }
            }
        }
        return nil
    }

    private static func sanitizedProviderMessage(_ message: String) -> String? {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return String(clean.prefix(240))
    }

    private static func providerMessages(in value: Any, depth: Int) -> [String] {
        guard depth < 6 else { return [] }
        if let message = value as? String {
            return sanitizedProviderMessage(message).map { [$0] } ?? []
        }
        if let array = value as? [Any] {
            return Array(array.prefix(5).flatMap {
                providerMessages(in: $0, depth: depth + 1)
            }.prefix(5))
        }
        guard let dictionary = value as? [String: Any] else { return [] }

        // Follow only error fields. Do not inspect input/request/payload/metadata.
        for key in ["errors", "error", "detail", "message", "msg", "reason"] {
            guard let nested = dictionary[key] else { continue }
            let messages = providerMessages(in: nested, depth: depth + 1)
            guard !messages.isEmpty else { continue }
            let location = (dictionary["loc"] as? [Any])?.prefix(8).compactMap { part -> String? in
                if let name = part as? String { return name == "body" ? nil : String(name.prefix(80)) }
                if let index = part as? Int { return String(index) }
                return nil
            }.joined(separator: ".") ?? ""
            return location.isEmpty ? messages : messages.map { "\(location): \($0)" }
        }
        // Some providers put the error object inside the response envelope.
        if let nested = dictionary["data"] as? [String: Any] {
            return providerMessages(in: nested, depth: depth + 1)
        }
        return []
    }
}
