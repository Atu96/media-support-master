import Foundation

/// Luồng AI có thể kiểm thử bằng client giả, không cần API key và không gọi mạng.
///
/// Runtime truyền Gemini/Groq client thật từ `CloudAIService`; test truyền client giả
/// trả về dữ liệu cố định. Nhờ vậy prompt, JSON và việc ghi SRT được khóa regression.
enum CloudAIWorkflow {
    static func summarize(
        transcript: String,
        sourceLanguageHint: String?,
        outputLanguage: String,
        client: any CloudAIClient
    ) async throws -> String {
        let sample = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else {
            throw CloudAIError.emptyInput
        }

        let sourceLabel = sourceLanguageHint?.isEmpty == false
            ? sourceLanguageHint!
            : "auto"
        let prompt = """
        Tóm tắt transcript dưới đây thành 3–5 câu súc tích.
        Ngôn ngữ nguồn: \(sourceLabel).
        Ngôn ngữ đầu ra: \(outputLanguage).
        Chỉ trả về phần tóm tắt, không thêm tiêu đề hay lời giải thích.

        TRANSCRIPT:
        \(String(sample.prefix(60_000)))
        """

        let response = try await client.generate(
            CloudAIGenerationRequest(
                system: "Bạn là biên tập viên video đa ngôn ngữ. Tóm tắt chính xác, tự nhiên và giữ đúng ý.",
                user: prompt,
                expectsJSON: false,
                maxOutputTokens: 1_200
            )
        )
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudAIError.invalidResponse
        }
        return trimmed
    }

    static func translateSRT(
        input: URL,
        output: URL,
        targetLanguage: String,
        sourceLanguage: String,
        progress: @escaping @Sendable (String) -> Void,
        client: any CloudAIClient
    ) async throws {
        let content = try String(contentsOf: input, encoding: .utf8)
        let blocks = SRTDocument.parse(content)
        guard !blocks.isEmpty else {
            throw SRTDocumentError.emptyInput
        }

        let items = blocks.enumerated().map { TranslationRequestItem(id: $0.offset, text: $0.element.text) }
        let chunks = translationChunks(items)
        var translatedByID: [Int: String] = [:]
        translatedByID.reserveCapacity(blocks.count)

        for (chunkIndex, chunk) in chunks.enumerated() {
            progress("… Đang gửi phần \(chunkIndex + 1)/\(chunks.count) · \(translatedByID.count)/\(blocks.count) block")
            try await requestTranslations(
                for: chunk,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                isRecovery: false,
                client: client,
                progress: progress,
                translatedByID: &translatedByID
            )
            let completed = translatedByID.count
            progress("… Dịch phần \(chunkIndex + 1)/\(chunks.count) · \(completed)/\(blocks.count) block")

            // Provider đôi khi trả JSON hợp lệ nhưng bỏ sót 1–2 mục. Chỉ gửi lại
            // đúng các cue còn thiếu; không dịch lại cue đã nhận và không ghi file dở.
            var missing = chunk.filter { translatedByID[$0.id]?.isEmpty != false }
            var recoveryAttempt = 0
            while !missing.isEmpty, recoveryAttempt < missingTranslationRetryLimit {
                recoveryAttempt += 1
                progress("↻ Bổ sung \(missing.count) cue còn thiếu · lượt \(recoveryAttempt)/\(missingTranslationRetryLimit)")
                try await requestTranslations(
                    for: missing,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    isRecovery: true,
                    client: client,
                    progress: progress,
                    translatedByID: &translatedByID
                )
                missing = missing.filter { translatedByID[$0.id]?.isEmpty != false }
            }
            guard missing.isEmpty else { throw CloudAIError.incompleteTranslation }
        }

        let translated = try blocks.indices.map { index -> String in
            guard let text = translatedByID[index], !text.isEmpty else {
                throw CloudAIError.incompleteTranslation
            }
            return text
        }

        try Task.checkCancellation()
        try SRTDocument.write(blocks: blocks, translated: translated, to: output)
    }

    /// Cỡ này ưu tiên TPM Groq free: ngay cả text CJK (xấp xỉ 1 ký tự = 1 token),
    /// input + completion dự phòng vẫn dưới khoảng 7k token. Cue rất dài được giữ nguyên
    /// để không làm thay timing/subtitle boundary.
    private static let translationChunkCharacterBudget = 2_600
    private static let missingTranslationRetryLimit = 2

    private static func requestTranslations(
        for items: [TranslationRequestItem],
        sourceLanguage: String,
        targetLanguage: String,
        isRecovery: Bool,
        client: any CloudAIClient,
        progress: @escaping @Sendable (String) -> Void,
        translatedByID: inout [Int: String],
        repairDepth: Int = 0
    ) async throws {
        try Task.checkCancellation()
        do {
            try await requestTranslationBatch(
                for: items, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                isRecovery: isRecovery, client: client, progress: progress,
                translatedByID: &translatedByID,
                repairDepth: repairDepth
            )
        } catch let error as CloudAIError {
            // Schema/truncation only. Authentication, quota, network and cancellation
            // propagate immediately; never switch provider or retry a successful batch.
            switch error {
            case .invalidResponse, .truncatedResponse:
                guard repairDepth < 2 else { throw error }
                let middle = max(1, items.count / 2)
                let smaller = items.count > 1
                    ? [Array(items.prefix(middle)), Array(items.dropFirst(middle))] : [items]
                for batch in smaller {
                    try await requestTranslations(
                        for: batch, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                        isRecovery: true, client: client, progress: progress,
                        translatedByID: &translatedByID,
                        repairDepth: repairDepth + 1
                    )
                }
            default: throw error
            }
        }
    }

    private static func requestTranslationBatch(
        for items: [TranslationRequestItem],
        sourceLanguage: String,
        targetLanguage: String,
        isRecovery: Bool,
        client: any CloudAIClient,
        progress: @escaping @Sendable (String) -> Void,
        translatedByID: inout [Int: String],
        repairDepth: Int
    ) async throws {
        let payloadData = try JSONEncoder().encode(items)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw CloudAIError.invalidResponse
        }
        let prompt = translationPrompt(
            payloadJSON: payloadJSON,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            requiredItemCount: items.count,
            isRecovery: isRecovery
        )

        // A completion limit CAN truncate provider output. Smaller repair batches
        // reserve more space; the adapter rejects finish_reason=length explicitly.
        let response = try await client.generate(
            CloudAIGenerationRequest(
                system: "Bạn là dịch giả phụ đề chuyên nghiệp. Ưu tiên câu tự nhiên, ngắn gọn và đúng ngữ cảnh.",
                user: prompt,
                expectsJSON: true,
                maxOutputTokens: min(6_000, completionReservation(for: items) * (repairDepth + 1)),
                progress: progress
            )
        )
        let envelope = try decodeTranslations(response)
        let allowedIDs = Set(items.map(\.id))
        var seen = Set<Int>()
        guard envelope.translations.allSatisfy({ allowedIDs.contains($0.id) && seen.insert($0.id).inserted }) else {
            throw CloudAIError.invalidResponse
        }
        for item in envelope.translations {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            translatedByID[item.id] = text
        }
    }

    private static func translationChunks(_ items: [TranslationRequestItem]) -> [[TranslationRequestItem]] {
        var chunks: [[TranslationRequestItem]] = []
        var current: [TranslationRequestItem] = []
        var currentCharacters = 0

        for item in items {
            let itemCharacters = item.text.unicodeScalars.count + 24 // id + JSON overhead
            if !current.isEmpty,
               currentCharacters + itemCharacters > translationChunkCharacterBudget {
                chunks.append(current)
                current = []
                currentCharacters = 0
            }
            current.append(item)
            currentCharacters += itemCharacters
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func completionReservation(for chunk: [TranslationRequestItem]) -> Int {
        let sourceCharacters = chunk.reduce(0) { $0 + $1.text.unicodeScalars.count }
        return min(3_000, max(512, sourceCharacters + 256))
    }

    private static func translationPrompt(
        payloadJSON: String,
        sourceLanguage: String,
        targetLanguage: String,
        requiredItemCount: Int,
        isRecovery: Bool
    ) -> String {
        let recoveryInstruction = isRecovery
            ? "Đây là lượt bổ sung các mục đã bị thiếu ở response trước."
            : ""
        return """
        Dịch từng mục JSON từ \(sourceLanguage) sang \(targetLanguage).
        \(recoveryInstruction)
        Giữ nguyên id và thứ tự. Chỉ dịch trường text.
        Không thêm chú thích, không bỏ mục, không gộp mục.
        Kết quả bắt buộc có đúng \(requiredItemCount) mục và đủ mọi id trong INPUT.
        Trả về đúng một JSON object dạng:
        {"translations":[{"id":0,"text":"..."}]}

        INPUT:
        \(payloadJSON)
        """
    }

    private static func decodeTranslations(_ raw: String) throws -> TranslationEnvelope {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudAIError.invalidResponse }

        // JSON mode là lý tưởng nhưng fallback Groq có thể trả mảng trực tiếp,
        // code fence, hoặc gọi trường dịch là `translation`. Chấp nhận những
        // biến thể *cùng dữ liệu* này; phía dưới vẫn lọc ID hợp lệ và bắt buộc
        // đủ toàn bộ cue trước khi ghi SRT.
        for candidate in jsonCandidates(from: trimmed) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let envelope = try? JSONDecoder().decode(TranslationEnvelope.self, from: data) {
                return envelope
            }
            if let items = try? JSONDecoder().decode([TranslationItem].self, from: data) {
                return TranslationEnvelope(translations: items)
            }
        }
        throw CloudAIError.invalidResponse
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        var value = raw
        if value.hasPrefix("```"), value.hasSuffix("```"),
           let newline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: newline)...].dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Never strip fences INSIDE translated text, and never salvage a nested
        // array from a truncated/invalid object (that could accept only half a job).
        if value.hasPrefix("{") || value.hasPrefix("[") { return [value] }
        guard let first = value.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let last = value.lastIndex(where: { $0 == "}" || $0 == "]" }), first < last else {
            return [value]
        }
        return [String(value[first...last])]
    }
}

private struct TranslationRequestItem: Encodable {
    let id: Int
    let text: String
}

private struct TranslationEnvelope: Decodable {
    let translations: [TranslationItem]

    init(translations: [TranslationItem]) {
        self.translations = translations
    }

    private enum CodingKeys: String, CodingKey {
        case translations
        case items
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translations = try container.decodeIfPresent([TranslationItem].self, forKey: .translations)
            ?? container.decodeIfPresent([TranslationItem].self, forKey: .items)
            ?? container.decode([TranslationItem].self, forKey: .results)
    }
}

private struct TranslationItem: Decodable {
    let id: Int
    let text: String

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case translation
        case translatedText
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericID = try? container.decode(Int.self, forKey: .id) {
            id = numericID
        } else if let stringID = try? container.decode(String.self, forKey: .id),
                  let numericID = Int(stringID) {
            id = numericID
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Translation item thiếu id số")
        }
        text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .translation)
            ?? container.decodeIfPresent(String.self, forKey: .translatedText)
            ?? container.decode(String.self, forKey: .content)
    }
}
