import Foundation

enum SubtitleTranslationMode: String, CaseIterable, Identifiable, Sendable {
    case appleLocal
    case gemini
    case groq

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleLocal: "Apple Local · Dự phòng"
        case .gemini: "Gemini API"
        case .groq: "Groq API"
        }
    }

    var hint: String {
        switch self {
        case .appleLocal:
            "Offline, riêng tư — dùng khi máy hỗ trợ Apple Intelligence"
        case .gemini:
            "Dịch + tóm tắt online bằng Gemini"
        case .groq:
            "Dịch + tóm tắt online tốc độ cao bằng Groq"
        }
    }

    var requiresInternet: Bool {
        self != .appleLocal
    }

    var icon: String {
        switch self {
        case .appleLocal: "apple.logo"
        case .gemini: "sparkles"
        case .groq: "bolt.horizontal.fill"
        }
    }
}
