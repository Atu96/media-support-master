import Foundation

/// Thông báo ngắn gọn cho người dùng; chi tiết gốc vẫn nằm trong Nhật ký.
struct CloudAIErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let settingsTab: SettingsModuleTab?
    let offersOfflineWhisper: Bool

    init(
        title: String,
        message: String,
        settingsTab: SettingsModuleTab?,
        offersOfflineWhisper: Bool = false
    ) {
        self.title = title
        self.message = message
        self.settingsTab = settingsTab
        self.offersOfflineWhisper = offersOfflineWhisper
    }
}

enum CloudAIErrorClassifier {
    static func alert(for error: Error) -> CloudAIErrorAlert? {
        if error is CancellationError { return nil }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .timedOut:
                return CloudAIErrorAlert(
                    title: "Không kết nối được Internet",
                    message: "Kiểm tra mạng rồi thử lại. Phụ đề và dữ liệu dự án của bạn vẫn được giữ nguyên.",
                    settingsTab: nil
                )
            default:
                return nil
            }
        }

        guard let cloudError = error as? CloudAIError else { return nil }
        switch cloudError {
        case let .missingKey(provider):
            return CloudAIErrorAlert(
                title: "Chưa có API key \(provider)",
                message: "Nhập key trong Cài đặt để tiếp tục. Dữ liệu dự án không bị thay đổi.",
                settingsTab: provider == "Gemini" ? .gemini : .groq
            )
        case let .http(status, message):
            return alert(forHTTPStatus: status, message: message)
        case let .rateLimited(retryAfterSeconds):
            let wait = retryAfterSeconds.map { " Groq đề nghị chờ khoảng \(Int(ceil($0))) giây." } ?? ""
            return CloudAIErrorAlert(
                title: "Groq đang giới hạn tốc độ",
                message: "Tác vụ dịch chưa hoàn tất.\(wait) File phụ đề hiện có vẫn được giữ nguyên.",
                settingsTab: nil
            )
        default:
            return nil
        }
    }

    private static func alert(forHTTPStatus status: Int, message: String) -> CloudAIErrorAlert? {
        let lowercased = message.lowercased()
        if status == 401 || status == 403 {
            return CloudAIErrorAlert(
                title: "API key không hợp lệ hoặc đã hết quyền",
                message: "Kiểm tra lại key và quyền truy cập của nhà cung cấp rồi thử lại.",
                settingsTab: lowercased.contains("gemini") ? .gemini : .groq
            )
        }
        if status == 429 {
            let quotaTerms = ["quota", "credit", "billing", "insufficient", "payment"]
            if quotaTerms.contains(where: lowercased.contains) {
                return CloudAIErrorAlert(
                    title: "Đã hết quota API",
                    message: "Nhà cung cấp hiện không còn lượt xử lý cho key/tài khoản này. Bạn có thể đổi key hoặc dùng nhà cung cấp khác.",
                    settingsTab: lowercased.contains("gemini") ? .gemini : .groq
                )
            }
            return CloudAIErrorAlert(
                title: "Đang chạm giới hạn gửi yêu cầu",
                message: "Hãy chờ một lúc rồi bấm lại. App không tự gửi lại nên không phát sinh lượt gọi ngoài ý muốn.",
                settingsTab: nil
            )
        }
        if status == 408 || (500...599).contains(status) {
            return CloudAIErrorAlert(
                title: "Dịch vụ AI đang tạm thời gặp sự cố",
                message: "Đây là lỗi phía nhà cung cấp. Hãy thử lại sau; phụ đề và dữ liệu dự án vẫn an toàn.",
                settingsTab: nil
            )
        }
        return nil
    }
}
