import Foundation

struct CloudAIGenerationRequest {
    let system: String
    let user: String
    let expectsJSON: Bool
    let maxOutputTokens: Int?
    let progress: (@Sendable (String) -> Void)?

    init(
        system: String,
        user: String,
        expectsJSON: Bool,
        maxOutputTokens: Int?,
        progress: (@Sendable (String) -> Void)? = nil
    ) {
        self.system = system
        self.user = user
        self.expectsJSON = expectsJSON
        self.maxOutputTokens = maxOutputTokens
        self.progress = progress
    }
}

protocol CloudAIClient {
    func generate(_ request: CloudAIGenerationRequest) async throws -> String
}

enum CloudAIError: LocalizedError {
    case emptyInput
    case missingKey(provider: String)
    case invalidEndpoint
    case invalidResponse
    case truncatedResponse
    case incompleteTranslation
    case invalidProvider
    case rateLimited(retryAfterSeconds: Double?)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Chưa có nội dung để gửi AI."
        case let .missingKey(provider):
            "Thiếu \(provider) API key — mở Cài đặt để nhập key."
        case .invalidEndpoint:
            "Địa chỉ dịch vụ AI không hợp lệ."
        case .invalidResponse:
            "AI trả về dữ liệu không đúng định dạng."
        case .truncatedResponse:
            "AI đã dừng do giới hạn đầu ra — bản dịch chưa hoàn tất, chưa ghi đè file."
        case .incompleteTranslation:
            "AI trả thiếu một số câu phụ đề — chưa ghi đè file."
        case .invalidProvider:
            "Apple Local phải được xử lý trực tiếp trên máy."
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                "Groq đang giới hạn tốc độ. Hãy thử lại sau khoảng \(Int(ceil(retryAfterSeconds))) giây; file phụ đề cũ vẫn được giữ."
            } else {
                "Groq đang giới hạn tốc độ. Hãy chờ rồi thử lại; file phụ đề cũ vẫn được giữ."
            }
        case let .http(status, message):
            "Lỗi API \(status): \(message)"
        }
    }
}
