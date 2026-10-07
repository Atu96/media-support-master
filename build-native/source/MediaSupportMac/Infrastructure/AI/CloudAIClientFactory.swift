import Foundation

/// Chọn client thật cho runtime. Test core không biên dịch file này nên không thể
/// vô tình đọc Keychain hoặc gọi mạng.
enum CloudAIClientFactory {
    static func make(for provider: SubtitleTranslationMode) throws -> any CloudAIClient {
        switch provider {
        case .appleLocal:
            throw CloudAIError.invalidProvider
        case .gemini:
            return GeminiAIClient()
        case .groq:
            return GroqAIClient()
        }
    }
}
