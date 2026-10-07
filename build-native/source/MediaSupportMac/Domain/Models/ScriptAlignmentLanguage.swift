import Foundation

/// Ngôn ngữ của kịch bản dùng để canh lời với audio.
enum ScriptAlignmentLanguage: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"
    case russian = "ru"
    case english = "en"
    case vietnamese = "vi"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
    case german = "de"
    case italian = "it"

    private static let storageKey = "msm.subtitle.scriptAlignmentLanguage"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Tự nhận diện"
        case .japanese: "Tiếng Nhật"
        case .chinese: "Tiếng Trung"
        case .korean: "Tiếng Hàn"
        case .russian: "Tiếng Nga"
        case .english: "Tiếng Anh"
        case .vietnamese: "Tiếng Việt"
        case .french: "Tiếng Pháp"
        case .spanish: "Tiếng Tây Ban Nha"
        case .portuguese: "Tiếng Bồ Đào Nha"
        case .german: "Tiếng Đức"
        case .italian: "Tiếng Ý"
        }
    }

    static func load() -> ScriptAlignmentLanguage {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = ScriptAlignmentLanguage(rawValue: raw)
        else { return .auto }
        return value
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}
