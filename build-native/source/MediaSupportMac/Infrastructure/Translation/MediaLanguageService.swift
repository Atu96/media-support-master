import Foundation
import NaturalLanguage

enum MediaLanguageService {
    static func resolveSource(
        userInput: String,
        mediaURL: URL?,
        srtURL: URL?
    ) -> MediaLanguageDetection {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty, trimmed != "auto" {
            return .user(AppleSRTTranslator.normalizeLangCode(trimmed))
        }

        if let mediaURL, let record = ProjectBackupStore.languageRecord(for: mediaURL) {
            return .whisper(record)
        }

        if let record = MediaLanguageRecord.load(near: mediaURL)
            ?? MediaLanguageRecord.load(near: srtURL) {
            return .whisper(record)
        }

        if let srtURL,
           let content = try? String(contentsOf: srtURL, encoding: .utf8) {
            let blocks = SRTDocument.parse(content)
            let text = blocks.map(\.text).joined(separator: "\n")
            if let detected = detectFromText(text) {
                return .srtText(detected.code, confidence: detected.confidence)
            }
        }

        return .fallback("en")
    }

    static func detectFromText(_ text: String) -> (code: String, confidence: Double?)? {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= 12 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let top = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        let code = AppleSRTTranslator.normalizeLangCode(top.key.rawValue.lowercased())
        return (code, top.value)
    }

    static func appleLanguageCode(from detection: MediaLanguageDetection) -> String {
        AppleSRTTranslator.normalizeLangCode(detection.code)
    }
}