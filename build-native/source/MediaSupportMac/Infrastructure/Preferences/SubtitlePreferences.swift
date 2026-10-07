import Foundation

@MainActor
final class SubtitlePreferences: ObservableObject {
    static let shared = SubtitlePreferences()

    private let modeKey = "msm.translationMode"
    private let appleRestoreMigrationKey = "msm.appleLocalBackupRestoreMigrated"
    private let summaryLangKey = "msm.summaryOutputLang"

    struct SummaryLanguageOption: Identifiable, Sendable {
        let code: String
        let label: String
        var id: String { code }
    }

    static let summaryLanguageOptions: [SummaryLanguageOption] = [
        SummaryLanguageOption(code: "vi", label: "Tiếng Việt"),
        SummaryLanguageOption(code: "en", label: "Tiếng Anh"),
        SummaryLanguageOption(code: "ja", label: "Tiếng Nhật"),
        SummaryLanguageOption(code: "zh", label: "Tiếng Trung"),
        SummaryLanguageOption(code: "ko", label: "Tiếng Hàn"),
        SummaryLanguageOption(code: "th", label: "Tiếng Thái"),
        SummaryLanguageOption(code: "auto", label: "Theo ngôn ngữ detect")
    ]

    @Published var translationMode: SubtitleTranslationMode {
        didSet {
            UserDefaults.standard.set(translationMode.rawValue, forKey: modeKey)
            Task { await refreshEngineStatus() }
        }
    }

    @Published var summaryOutputLang: String {
        didSet {
            let normalized = Self.normalizeSummaryLang(summaryOutputLang)
            if normalized != summaryOutputLang {
                summaryOutputLang = normalized
                return
            }
            UserDefaults.standard.set(summaryOutputLang, forKey: summaryLangKey)
        }
    }

    @Published private(set) var engineReady = true
    @Published private(set) var engineStatusTitle = "Sẵn sàng"
    @Published private(set) var engineStatusDetail = ""
    @Published private(set) var geminiQuotaExceeded = false
    @Published private(set) var detectedSourceLabel = ""
    @Published private(set) var activeTargetLang = "vi"

    private var lastMediaURL: URL?
    private var lastSRTURL: URL?
    private var lastSourceLang = "auto"
    private var lastTargetLang = "vi"

    private init() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: modeKey)
        // Bản từng bỏ Apple Local có thể còn raw cũ; khi phục hồi không tự giành lại mặc định cloud.
        if raw == SubtitleTranslationMode.appleLocal.rawValue,
           !defaults.bool(forKey: appleRestoreMigrationKey) {
            translationMode = .gemini
            defaults.set(SubtitleTranslationMode.gemini.rawValue, forKey: modeKey)
        } else {
            translationMode = SubtitleTranslationMode(rawValue: raw ?? "") ?? .gemini
        }
        defaults.set(true, forKey: appleRestoreMigrationKey)
        let savedSummary = UserDefaults.standard.string(forKey: summaryLangKey) ?? "vi"
        summaryOutputLang = Self.normalizeSummaryLang(savedSummary)
        Task { await refreshEngineStatus() }
    }

    var summaryOutputLabel: String {
        Self.summaryLanguageOptions.first { $0.code == summaryOutputLang }?.label ?? summaryOutputLang
    }

    func resolvedSummaryLanguage(detectedSource: String?) -> String {
        if summaryOutputLang == "auto" {
            if let detectedSource, !detectedSource.isEmpty {
                return AppleSRTTranslator.normalizeLangCode(detectedSource)
            }
            return "vi"
        }
        return summaryOutputLang
    }

    private static func normalizeSummaryLang(_ raw: String) -> String {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if summaryLanguageOptions.contains(where: { $0.code == code }) {
            return code
        }
        return "vi"
    }

    var canTranslate: Bool {
        switch translationMode {
        case .appleLocal:
            return engineReady
        case .gemini:
            if geminiQuotaExceeded { return false }
            return GeminiCredentialStore.hasKey
        case .groq:
            return GroqCredentialStore.hasKey
        }
    }

    var selectedProviderHasKey: Bool {
        switch translationMode {
        case .appleLocal:
            true
        case .gemini:
            GeminiCredentialStore.hasKey
        case .groq:
            GroqCredentialStore.hasKey
        }
    }

    var actionHint: String? {
        switch translationMode {
        case .appleLocal:
            return engineReady ? nil : engineStatusDetail
        case .gemini:
            if geminiQuotaExceeded {
                return "Key Gemini hết quota — vào Cài đặt → Gemini để đổi key"
            }
            return GeminiCredentialStore.hasKey ? nil : "Nhập Gemini API key trong Cài đặt → Gemini"
        case .groq:
            return GroqCredentialStore.hasKey ? nil : "Nhập Groq API key trong Cài đặt → Groq"
        }
    }

    var canSummarize: Bool {
        switch translationMode {
        case .appleLocal:
            AppleLocalSummaryAvailability.isAvailable
        case .gemini, .groq:
            canTranslate
        }
    }

    var summaryActionHint: String? {
        if translationMode == .appleLocal, !AppleLocalSummaryAvailability.isAvailable {
            return AppleLocalSummaryAvailability.detail
        }
        return actionHint
    }

    func markGeminiQuotaExceeded() {
        guard translationMode == .gemini else { return }
        geminiQuotaExceeded = true
        engineReady = false
        engineStatusTitle = "Hết quota"
        engineStatusDetail = "Key hiện tại hết usage — mở Cài đặt → Gemini để đổi key dự phòng"
    }

    func clearGeminiQuotaExceeded() {
        guard geminiQuotaExceeded else { return }
        geminiQuotaExceeded = false
        Task { await refreshEngineStatus() }
    }

    func updateContext(
        mediaURL: URL?,
        srtURL: URL?,
        sourceLang: String,
        targetLang: String
    ) {
        lastMediaURL = mediaURL
        lastSRTURL = srtURL
        lastSourceLang = sourceLang
        lastTargetLang = targetLang
        activeTargetLang = targetLang

        let detection = MediaLanguageService.resolveSource(
            userInput: sourceLang,
            mediaURL: mediaURL,
            srtURL: srtURL
        )
        detectedSourceLabel = detection.label

        Task { await refreshEngineStatus() }
    }

    func refreshEngineStatus() async {
        switch translationMode {
        case .appleLocal:
            let detection = MediaLanguageService.resolveSource(
                userInput: lastSourceLang,
                mediaURL: lastMediaURL,
                srtURL: lastSRTURL
            )
            let source = MediaLanguageService.appleLanguageCode(from: detection)
            let target = AppleSRTTranslator.normalizeLangCode(lastTargetLang)
            detectedSourceLabel = detection.label

            let support = await AppleSRTTranslator.checkSupport(
                source: source,
                target: target
            )
            switch support {
            case .ready:
                engineReady = true
                engineStatusTitle = "Apple Local sẵn sàng"
                engineStatusDetail = "\(source) → \(target) · \(AppleLocalSummaryAvailability.detail)"
            case .needsDownload:
                engineReady = true
                engineStatusTitle = "Cần tải gói dịch"
                engineStatusDetail = "\(source) → \(target) · tải gói Apple ở bên dưới"
            case .unsupported:
                engineReady = false
                engineStatusTitle = "Cặp ngôn ngữ không hỗ trợ"
                engineStatusDetail = "Apple Local không hỗ trợ \(source) → \(target); hãy dùng Gemini/Groq"
            case .unavailableOS:
                engineReady = false
                engineStatusTitle = "Apple Local không khả dụng"
                engineStatusDetail = "Bản macOS/máy này không hỗ trợ; Gemini/Groq vẫn dùng bình thường"
            }
            return
        case .gemini:
            if geminiQuotaExceeded {
                engineReady = false
                engineStatusTitle = "Hết quota"
                engineStatusDetail = "Key hiện tại hết usage — mở Cài đặt → Gemini để đổi key"
                return
            }
            engineReady = GeminiCredentialStore.hasKey
            engineStatusTitle = engineReady ? "Sẵn sàng" : "Thiếu API key"
            engineStatusDetail = engineReady
                ? "Gemini — dùng chung cho Dịch và Tóm tắt"
                : "Mở Cài đặt → Gemini để nhập key"
            return
        case .groq:
            engineReady = GroqCredentialStore.hasKey
            engineStatusTitle = engineReady ? "Sẵn sàng" : "Thiếu API key"
            engineStatusDetail = engineReady
                ? "Groq \(GroqModelPreferences.selectedTextModel.label) — Dịch và Tóm tắt"
                : "Mở Cài đặt → Groq để nhập key"
            return
        }
    }
}
