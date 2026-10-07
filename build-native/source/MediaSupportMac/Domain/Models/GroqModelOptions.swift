import Foundation

enum GroqTextModel: String, CaseIterable, Identifiable, Sendable {
    case quality = "openai/gpt-oss-120b"
    case qwenAsian = "qwen/qwen3.6-27b"
    case fast = "openai/gpt-oss-20b"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: "GPT-OSS 120B"
        case .qwenAsian: "Qwen 3.6 27B"
        case .fast: "GPT-OSS 20B"
        }
    }

    var menuLabel: String {
        switch self {
        case .quality: "\(label) · Khuyên dùng"
        case .qwenAsian: "\(label) · Nhật/Trung · Preview"
        case .fast: "\(label) · Nhanh, tiết kiệm"
        }
    }

    var detail: String {
        switch self {
        case .quality:
            "Khuyên dùng cho dịch phụ đề và tóm tắt: hiểu ngữ cảnh, đa ngôn ngữ tốt hơn."
        case .qwenAsian:
            "Đáng thử cho nội dung Nhật, Trung, Việt và Anh. Đây là mô hình Preview của Groq nên chưa dùng làm mặc định."
        case .fast:
            "Phản hồi nhanh và tiết kiệm hơn; hợp nội dung đơn giản hoặc cần xử lý số lượng lớn."
        }
    }
}

enum GroqSpeechModel: String, CaseIterable, Identifiable, Sendable {
    case turbo = "whisper-large-v3-turbo"
    case quality = "whisper-large-v3"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .turbo: "Whisper Large V3 Turbo"
        case .quality: "Whisper Large V3"
        }
    }

    var shortLabel: String {
        switch self {
        case .turbo: "Whisper V3 Turbo"
        case .quality: "Whisper V3"
        }
    }

    var menuLabel: String {
        switch self {
        case .turbo: "\(label) · Khuyên dùng"
        case .quality: "\(label) · Chính xác nhất"
        }
    }

    var detail: String {
        switch self {
        case .turbo:
            "Khuyên dùng để tạo sub hằng ngày: rất nhanh, đa ngôn ngữ và tối ưu chi phí."
        case .quality:
            "Dùng khi âm thanh khó, nhiều tạp âm hoặc cần ưu tiên độ chính xác cao nhất."
        }
    }
}

enum GroqModelPreferences {
    static let textModelKey = "msm.groq.textModel"
    static let speechModelKey = "msm.groq.speechModel"
    static let semanticCuePlanningKey = "msm.groq.semanticCuePlanning"

    static var selectedTextModel: GroqTextModel {
        let raw = UserDefaults.standard.string(forKey: textModelKey)
        return GroqTextModel(rawValue: raw ?? "") ?? .quality
    }

    static var selectedSpeechModel: GroqSpeechModel {
        let raw = UserDefaults.standard.string(forKey: speechModelKey)
        return GroqSpeechModel(rawValue: raw ?? "") ?? .turbo
    }

    static var semanticCuePlanningEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: semanticCuePlanningKey) != nil else { return true }
        return defaults.bool(forKey: semanticCuePlanningKey)
    }
}
