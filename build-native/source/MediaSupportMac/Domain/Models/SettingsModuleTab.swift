import Foundation

enum SettingsModuleTab: String, CaseIterable, Identifiable, Sendable {
    case translate
    case groq
    case gemini
    case offlineWhisper
    case dubbing
    case appearance
    case backup
    case system
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: "Ngôn ngữ & AI"
        case .gemini: "Gemini"
        case .groq: "Groq"
        case .offlineWhisper: "Whisper Offline"
        case .dubbing: "Lồng tiếng"
        case .appearance: "Giao diện"
        case .backup: "Lưu trữ"
        case .system: "Chẩn đoán"
        case .about: "Giới thiệu"
        }
    }

    var icon: String {
        switch self {
        case .translate: "character.book.closed"
        case .gemini: "key.fill"
        case .groq: "bolt.horizontal.fill"
        case .offlineWhisper: "arrow.down.circle.fill"
        case .dubbing: "waveform.badge.mic"
        case .appearance: "paintpalette.fill"
        case .backup: "externaldrive.fill"
        case .system: "gearshape.2"
        case .about: "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .translate: "Dịch, tóm tắt và ngôn ngữ mặc định"
        case .gemini: "Kết nối dịch vụ Google Gemini"
        case .groq: "Kết nối và chọn mô hình Groq"
        case .offlineWhisper: "Chép lời trên máy khi không có mạng"
        case .dubbing: "Google TTS, Eleven v3 và Apple Offline"
        case .appearance: "Chế độ màu và khả năng hiển thị"
        case .backup: "Bản sao dự án và tệp xuất"
        case .system: "Kiểm tra tình trạng ứng dụng"
        case .about: "Thông tin ứng dụng và ủng hộ tác giả"
        }
    }
}
