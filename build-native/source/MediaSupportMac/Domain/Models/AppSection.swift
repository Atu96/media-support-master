import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case subtitleScript
    case subtitleCreate

    var id: String { rawValue }

    /// Thứ tự hàng nav chính của khu vực phụ đề.
    static var mainNav: [AppSection] {
        [.subtitleCreate, .subtitleScript]
    }

    var title: String {
        switch self {
        case .subtitleScript: "Khớp văn bản gốc"
        case .subtitleCreate: "Tạo sub tự động"
        }
    }

    var navTitle: String { title }

    var pageSubtitle: String {
        switch self {
        case .subtitleScript: "Giữ nguyên văn bản — khớp thời gian theo media"
        case .subtitleCreate: "Groq Whisper online — tạo và chỉnh sub"
        }
    }

    var icon: String {
        switch self {
        case .subtitleScript: "doc.text"
        case .subtitleCreate: "waveform"
        }
    }

    var subtitleModuleTab: SubtitleModuleTab {
        switch self {
        case .subtitleScript: .script
        case .subtitleCreate: .create
        }
    }

    var usesFullScreenWindow: Bool { true }
}
