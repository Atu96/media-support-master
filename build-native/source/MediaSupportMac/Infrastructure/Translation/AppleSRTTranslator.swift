import Foundation
import NaturalLanguage

#if canImport(Translation)
import Translation
#endif

enum AppleTranslationSupport {
    case ready
    case needsDownload
    case unsupported
    case unavailableOS

    var message: String {
        switch self {
        case .ready: "Sẵn sàng dịch offline"
        case .needsDownload: "Cần tải gói ngôn ngữ — xem Cài đặt"
        case .unsupported: "Cặp ngôn ngữ này không được Apple hỗ trợ"
        case .unavailableOS: "Cần macOS 26 trở lên cho Apple local"
        }
    }
}

enum AppleSRTTranslator {
    static func resolveSourceLang(_ sourceLang: String, sampleText: String) -> String {
        let trimmed = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty || trimmed == "auto" else {
            return normalizeLangCode(trimmed)
        }
        if let detected = MediaLanguageService.detectFromText(sampleText) {
            return detected.code
        }
        return "en"
    }

    static func normalizeLangCode(_ code: String) -> String {
        let c = code.lowercased()
        if c.hasPrefix("zh") { return "zh" }
        if c == "jp" { return "ja" }
        return c.split(separator: "-").first.map(String.init) ?? c
    }

    static func checkSupport(source: String, target: String) async -> AppleTranslationSupport {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else { return .unavailableOS }
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
        switch status {
        case .installed:
            return .ready
        case .supported:
            return .needsDownload
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
        #else
        return .unavailableOS
        #endif
    }

    static func translate(
        input: URL,
        output: URL,
        targetLang: String,
        sourceLang: String,
        mediaURL: URL?,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            throw AppleSRTTranslatorError.unavailableOS
        }

        let content = try String(contentsOf: input, encoding: .utf8)
        let blocks = SRTDocument.parse(content)
        guard !blocks.isEmpty else { throw SRTDocumentError.emptyInput }

        let target = normalizeLangCode(targetLang)
        let detection = MediaLanguageService.resolveSource(
            userInput: sourceLang,
            mediaURL: mediaURL,
            srtURL: input
        )
        let source = MediaLanguageService.appleLanguageCode(from: detection)

        log("🔎 Ngôn ngữ nguồn: \(detection.label)")

        let support = await checkSupport(source: source, target: target)
        log("🍎 Apple local: \(source) → \(target) — \(support.message)")
        guard support != .unsupported, support != .unavailableOS else {
            throw AppleSRTTranslatorError.unsupportedPair(source: source, target: target)
        }

        if support == .needsDownload {
            log("💡 Gói chưa tải — vào Cài đặt → Gói ngôn ngữ Apple, hoặc macOS sẽ hỏi khi dịch")
        }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target)
        )

        var translated: [String] = []
        translated.reserveCapacity(blocks.count)

        for (index, block) in blocks.enumerated() {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                translated.append("")
            } else {
                let response = try await session.translate(text)
                translated.append(response.targetText)
            }
            if (index + 1) % 20 == 0 || index + 1 == blocks.count {
                log("… \(index + 1)/\(blocks.count) block")
            }
        }

        try SRTDocument.write(blocks: blocks, translated: translated, to: output)
        log("✅ Đã dịch \(blocks.count) block → \(output.path)")
        #else
        throw AppleSRTTranslatorError.unavailableOS
        #endif
    }
}

enum AppleSRTTranslatorError: LocalizedError {
    case unavailableOS
    case unsupportedPair(source: String, target: String)

    var errorDescription: String? {
        switch self {
        case .unavailableOS:
            "Apple local cần macOS 26+ và Translation.framework."
        case let .unsupportedPair(source, target):
            "Apple không hỗ trợ cặp \(source) → \(target)."
        }
    }
}