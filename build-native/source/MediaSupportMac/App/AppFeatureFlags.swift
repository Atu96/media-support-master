import Foundation

enum AppFeatureFlags {
    /// Dubbing là module chính thức. Giữ cờ để có thể tạo build chẩn đoán tắt
    /// module khi cần, nhưng app/build không khai báo khóa sẽ luôn bật.
    static var dubbingEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "MediaSupportDubbingEnabled") as? Bool ?? true
    }
}
