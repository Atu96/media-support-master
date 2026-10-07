import Foundation
import NaturalLanguage

/// Nhận diện cục bộ cho tab Kịch bản. Không gọi mạng/API và không đụng audio.
enum ScriptLanguageDetector {
    static func detect(from text: String) -> ScriptAlignmentLanguage? {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }

        // Script là tín hiệu chắc hơn recognizer, nhất là tiếng Nhật có lẫn Kanji.
        if contains(sample, in: 0x3040...0x30FF) || contains(sample, in: 0x31F0...0x31FF) {
            return .japanese
        }
        if contains(sample, in: 0x4E00...0x9FFF) {
            return .chinese
        }
        if contains(sample, in: 0xAC00...0xD7AF) {
            return .korean
        }
        if contains(sample, in: 0x0400...0x052F) {
            return .russian
        }

        guard sample.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let top = recognizer.dominantLanguage else { return nil }
        let code = top.rawValue.lowercased().split(separator: "-").first.map(String.init) ?? ""
        return ScriptAlignmentLanguage(rawValue: code)
    }

    private static func contains(_ text: String, in range: ClosedRange<UInt32>) -> Bool {
        text.unicodeScalars.contains { range.contains($0.value) }
    }
}
