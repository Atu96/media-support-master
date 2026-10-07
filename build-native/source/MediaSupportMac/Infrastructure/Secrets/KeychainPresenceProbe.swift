import Foundation
import LocalAuthentication
import Security

/// Kiểm tra item Keychain để vẽ trạng thái UI mà tuyệt đối không bật hộp xác thực.
enum KeychainPresenceProbe {
    static func contains(service: String, account: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // interactionNotAllowed nghĩa là item tồn tại nhưng chỉ được mở khi user
        // thực sự gọi API; UI trạng thái vẫn xem đó là đã lưu key.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}
