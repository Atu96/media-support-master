import Foundation

enum ElevenLabsRequestEncoder {
    static func body(_ request: DubbingSpeechRequest) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "text": request.text,
            "model_id": request.modelIdentifier,
            "language_code": Locale(identifier: request.localeIdentifier).language.languageCode?.identifier ?? "vi",
            "voice_settings": ["speed": min(1.2, max(0.7, Double(request.rate / 0.5)))],
        ], options: [.sortedKeys])
    }
}
