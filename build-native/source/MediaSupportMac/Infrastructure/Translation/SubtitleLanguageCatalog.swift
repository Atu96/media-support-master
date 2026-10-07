import Foundation

/// Danh mục ngôn ngữ đích — tên hiển thị theo Locale hệ thống.
enum SubtitleLanguageCatalog {
    struct LanguageOption: Identifiable, Hashable, Sendable {
        let code: String
        var id: String { code }

        var localizedName: String {
            let locale = Locale.current
            if let name = locale.localizedString(forLanguageCode: code), !name.isEmpty {
                return name
            }
            if code.contains("-"), let base = code.split(separator: "-").first,
               let name = locale.localizedString(forLanguageCode: String(base)), !name.isEmpty {
                return name
            }
            return code.uppercased()
        }

        var displayTitle: String {
            let token = code.uppercased()
            let name = localizedName
            if name.caseInsensitiveCompare(token) == .orderedSame
                || name.caseInsensitiveCompare(code) == .orderedSame {
                return name
            }
            return "\(name) — \(token)"
        }

        /// Mã ngắn trên nút «Dịch (Vi)» — phân biệt zh-Hans / zh-Hant, pt-BR, …
        var shortToken: String {
            let parts = code.split(separator: "-", maxSplits: 1).map(String.init)
            let base = parts[0]
            guard !base.isEmpty else { return code.uppercased() }
            let head = base.prefix(1).uppercased() + base.dropFirst().lowercased()
            guard parts.count > 1 else { return head }
            return "\(head)-\(parts[1])"
        }
    }

    private static let recentKey = "msm.translateTargetLangHistory"
    private static let maxRecent = 6

    /// Thứ tự ưu tiên — app hỗ trợ dịch sub (Apple / Gemini).
    private static let orderedCodes: [String] = [
        "vi", "en", "ja", "ko", "zh-Hans", "zh-Hant", "th", "fr", "de", "es", "it", "pt", "pt-BR",
        "ru", "ar", "hi", "id", "ms", "fil", "nl", "pl", "tr", "uk", "sv", "da", "nb", "fi", "cs",
        "sk", "hu", "ro", "el", "he", "bn", "ta", "te", "mr", "gu", "kn", "ml", "pa", "ur", "fa",
        "sw", "ca", "hr", "sl", "bg", "sr", "lt", "lv", "et", "is", "ga", "cy", "sq", "mk", "bs",
        "az", "kk", "uz", "mn", "my", "km", "lo", "ne", "si", "am", "zu", "af", "eu", "gl", "be"
    ]

    static var targetLanguages: [LanguageOption] {
        var seen = Set<String>()
        var result: [LanguageOption] = []
        for raw in orderedCodes {
            let code = AppleSRTTranslator.normalizeLangCode(raw)
            guard seen.insert(code).inserted else { continue }
            result.append(LanguageOption(code: code))
        }
        return result
    }

    static func option(for code: String) -> LanguageOption? {
        let normalized = AppleSRTTranslator.normalizeLangCode(code)
        return targetLanguages.first { $0.code == normalized }
            ?? LanguageOption(code: normalized)
    }

    static func displayTitle(for code: String) -> String {
        option(for: code)?.displayTitle ?? code.uppercased()
    }

    static func shortToken(for code: String) -> String {
        option(for: code)?.shortToken ?? code.uppercased()
    }

    static func recentCodes() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        return saved.filter { code in
            targetLanguages.contains { $0.code == AppleSRTTranslator.normalizeLangCode(code) }
        }
    }

    static func recordRecent(_ code: String) {
        let normalized = AppleSRTTranslator.normalizeLangCode(code)
        var history = recentCodes().filter { $0 != normalized }
        history.insert(normalized, at: 0)
        if history.count > maxRecent {
            history = Array(history.prefix(maxRecent))
        }
        UserDefaults.standard.set(history, forKey: recentKey)
    }

    static func menuCodes(prioritizing selected: String) -> [String] {
        let normalized = AppleSRTTranslator.normalizeLangCode(selected)
        var seen = Set<String>()
        var codes: [String] = []
        for code in recentCodes() + [normalized] {
            let norm = AppleSRTTranslator.normalizeLangCode(code)
            guard seen.insert(norm).inserted else { continue }
            codes.append(norm)
        }
        for lang in targetLanguages where seen.insert(lang.code).inserted {
            codes.append(lang.code)
        }
        return codes
    }
}