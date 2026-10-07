import Foundation

#if canImport(Translation)
import Translation
#endif

enum AppleLanguagePackStatus: String, Sendable {
    case installed
    case needsDownload
    case unsupported

    var label: String {
        switch self {
        case .installed: "Đã tải"
        case .needsDownload: "Chưa tải"
        case .unsupported: "Không hỗ trợ"
        }
    }

    var isReady: Bool {
        self == .installed
    }
}

struct AppleLanguagePackRow: Identifiable, Sendable {
    let id: String
    let code: String
    let name: String
    let status: AppleLanguagePackStatus
    let targetLang: String
}

@MainActor
final class AppleLanguagePackManager: ObservableObject {
    static let shared = AppleLanguagePackManager()

    @Published private(set) var rows: [AppleLanguagePackRow] = []
    @Published private(set) var isRefreshing = false
    @Published var downloadMessage = ""
    @Published var activeDownload: TranslationSession.Configuration?

    static let trackedSources: [(code: String, name: String)] = [
        ("ja", "Tiếng Nhật"),
        ("zh", "Tiếng Trung"),
        ("ko", "Tiếng Hàn"),
        ("en", "Tiếng Anh"),
        ("th", "Tiếng Thái"),
        ("fr", "Tiếng Pháp"),
        ("de", "Tiếng Đức"),
        ("es", "Tiếng Tây Ban Nha")
    ]

    private init() {}

    func refresh(targetLang: String = "vi") async {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            rows = []
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let availability = LanguageAvailability()
        let target = AppleSRTTranslator.normalizeLangCode(targetLang)
        var next: [AppleLanguagePackRow] = []

        for item in Self.trackedSources {
            let status = await availability.status(
                from: Locale.Language(identifier: item.code),
                to: Locale.Language(identifier: target)
            )
            let mapped: AppleLanguagePackStatus
            switch status {
            case .installed: mapped = .installed
            case .supported: mapped = .needsDownload
            case .unsupported: mapped = .unsupported
            @unknown default: mapped = .unsupported
            }
            next.append(
                AppleLanguagePackRow(
                    id: "\(item.code)-\(target)",
                    code: item.code,
                    name: item.name,
                    status: mapped,
                    targetLang: target
                )
            )
        }
        rows = next
        #else
        rows = []
        #endif
    }

    func requestDownload(source: String, target: String) {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            downloadMessage = "Cần macOS 26+"
            return
        }
        downloadMessage = "Đang yêu cầu tải gói \(source) → \(target)..."
        activeDownload = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target)
        )
        #endif
    }

    func finishDownload(success: Bool, source: String, target: String) {
        activeDownload = nil
        if success {
            downloadMessage = "Đã tải gói \(source) → \(target)"
        }
        Task { await refresh(targetLang: target) }
    }
}