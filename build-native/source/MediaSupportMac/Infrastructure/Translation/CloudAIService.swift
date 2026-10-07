import Foundation

/// Facade AI mà phần còn lại của app sử dụng.
///
/// Prompt/nghiệp vụ phụ đề ở đây; chi tiết REST của từng nhà cung cấp nằm trong
/// `Infrastructure/AI/Providers` để thêm hoặc thay model không lan sang UI.
enum CloudAIService {
    static let geminiModel = GeminiAIClient.model

    static func summarize(
        transcript: String,
        sourceLanguageHint: String?,
        outputLanguage: String,
        provider: SubtitleTranslationMode
    ) async throws -> String {
        let client = try CloudAIClientFactory.make(for: provider)
        return try await CloudAIWorkflow.summarize(
            transcript: transcript,
            sourceLanguageHint: sourceLanguageHint,
            outputLanguage: outputLanguage,
            client: client
        )
    }

    static func translateSRT(
        input: URL,
        output: URL,
        targetLanguage: String,
        sourceLanguage: String,
        provider: SubtitleTranslationMode,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        let client = try CloudAIClientFactory.make(for: provider)
        try await CloudAIWorkflow.translateSRT(
            input: input,
            output: output,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
            progress: progress,
            client: client
        )
    }
}
