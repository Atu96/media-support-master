import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum TranscriptSummaryService {
    static func summarize(
        transcript: String,
        sourceLanguageHint: String?,
        outputLanguage: String,
        provider: SubtitleTranslationMode
    ) async throws -> String {
        switch provider {
        case .appleLocal:
            return try await summarizeWithApple(
                transcript: transcript,
                sourceLanguageHint: sourceLanguageHint,
                outputLanguage: outputLanguage
            )
        case .gemini, .groq:
            return try await CloudAIService.summarize(
                transcript: transcript,
                sourceLanguageHint: sourceLanguageHint,
                outputLanguage: outputLanguage,
                provider: provider
            )
        }
    }

    private static func summarizeWithApple(
        transcript: String,
        sourceLanguageHint: String?,
        outputLanguage: String
    ) async throws -> String {
        let sample = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { throw CloudAIError.emptyInput }

        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw AppleLocalSummaryError.unavailable
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AppleLocalSummaryError.unavailable
        }

        let source = sourceLanguageHint?.isEmpty == false
            ? sourceLanguageHint!
            : "auto"
        let session = LanguageModelSession(model: model)
        let prompt = """
        Tóm tắt transcript dưới đây thành 3–5 câu súc tích.
        Ngôn ngữ nguồn: \(source).
        Ngôn ngữ đầu ra: \(outputLanguage).
        Chỉ trả về phần tóm tắt, không thêm tiêu đề hay giải thích.

        TRANSCRIPT:
        \(String(sample.prefix(12_000)))
        """
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudAIError.invalidResponse }
        return text
        #else
        throw AppleLocalSummaryError.unavailable
        #endif
    }
}

enum AppleLocalSummaryAvailability {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    static var detail: String {
        if isAvailable {
            return "Apple Intelligence sẵn sàng — tóm tắt hoàn toàn trên máy"
        }
        return "Tóm tắt local cần Mac hỗ trợ và đã bật Apple Intelligence"
    }
}

enum AppleLocalSummaryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Local chưa khả dụng — cần Mac hỗ trợ và bật Apple Intelligence."
    }
}
