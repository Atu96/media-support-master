import Foundation

enum AppLanguageSelectionPolicy {
    static let validCodes: Set<String> = ["system", "vi", "en", "ja", "ko", "zh-Hans"]

    static func resolve(saved: String?, legacy: String?) -> String {
        if let saved, validCodes.contains(saved) { return saved }
        if let legacy, validCodes.contains(legacy) { return legacy }
        return "en"
    }
}

enum AppSupportLink {
    static let url = URL(string: "https://ko-fi.com/atu1202")!
}
