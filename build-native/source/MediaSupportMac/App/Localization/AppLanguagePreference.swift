import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case vietnamese = "vi"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// Autonym giúp người dùng vẫn nhận ra lựa chọn ngay cả khi app đang ở ngôn ngữ lạ.
    var displayName: String {
        switch self {
        case .system: L10n.string("Theo hệ thống")
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .simplifiedChinese: "简体中文"
        }
    }

    fileprivate var appleLanguageCode: String? {
        self == .system ? nil : rawValue
    }
}

@MainActor
enum AppLanguagePreference {
    static let storageKey = "msm.appearance.appLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    static var selected: AppLanguage {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
        let code = AppLanguageSelectionPolicy.resolve(
            saved: defaults.string(forKey: storageKey),
            legacy: (domain?[appleLanguagesKey] as? [String])?.first
        )
        return AppLanguage(rawValue: code) ?? .english
    }

    /// Trước khi Bundle/menu/View tra localization lần đầu. Giữ lựa chọn hợp lệ
    /// kể cả System; cài mới và giá trị hỏng mới dùng English.
    static func prepareForLaunch() { apply(selected) }

    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: storageKey)
        if let code = language.appleLanguageCode {
            defaults.set([code], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        defaults.synchronize()
    }

    /// Mở đúng bundle đang chạy (TEST vẫn là TEST), rồi đóng instance cũ.
    static func relaunchCurrentBundle() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L10n.string("Không thể mở lại ứng dụng")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
