import Foundation
import LocalAuthentication
import Security

enum GoogleTTSCredentialStore {
    private static let service = "MediaSupportMaster.GoogleTTSAPIKey.v2"
    private static let account = "default"

    static func load() async -> String { await DubbingKeychainStore.load(service: service, account: account) }
    static func save(_ key: String) throws { try DubbingKeychainStore.save(key, service: service, account: account) }
    static func delete() throws { try DubbingKeychainStore.delete(service: service, account: account) }
    static var hasKey: Bool { DubbingKeychainStore.contains(service: service, account: account) }
}

enum ElevenLabsCredentialStore {
    private static let service = "MediaSupportMaster.ElevenLabsAPIKey.v2"
    private static let account = "default"

    static func load() async -> String { await DubbingKeychainStore.load(service: service, account: account) }
    static func save(_ key: String) throws { try DubbingKeychainStore.save(key, service: service, account: account) }
    static func delete() throws { try DubbingKeychainStore.delete(service: service, account: account) }
    static var hasKey: Bool { DubbingKeychainStore.contains(service: service, account: account) }
}

enum MaziaoCredentialStore {
    private static let service = "MediaSupportMaster.MaziaoAPIKey.v2"
    private static let account = "default"

    static func load() async -> String { await DubbingKeychainStore.load(service: service, account: account) }
    static func save(_ key: String) throws { try DubbingKeychainStore.save(key, service: service, account: account) }
    static func delete() throws { try DubbingKeychainStore.delete(service: service, account: account) }
    static var hasKey: Bool { DubbingKeychainStore.contains(service: service, account: account) }
}

/// Security.framework dùng API đồng bộ. Actor này bảo đảm các provider không
/// cùng giải mã/ghi một item Keychain trên nhiều task, đồng thời giữ công việc
/// đó ngoài MainActor. Secret chỉ tồn tại trong lời gọi provider đang chạy.
actor DubbingCredentialAccess {
    static let shared = DubbingCredentialAccess()
    private var googleLoadTask: Task<String, Never>?
    private var googleRevision = 0
    private var elevenLabsLoadTask: Task<String, Never>?
    private var elevenLabsRevision = 0
    private var maziaoLoadTask: Task<String, Never>?
    private var maziaoRevision = 0

    func loadGoogle() async -> String {
        let revision = googleRevision
        if let googleLoadTask {
            let value = await googleLoadTask.value
            return googleRevision == revision ? value : ""
        }
        let task = Task { await GoogleTTSCredentialStore.load() }
        googleLoadTask = task
        let value = await task.value
        guard googleRevision == revision else { return "" }
        googleLoadTask = nil
        return value
    }
    func saveGoogle(_ key: String) throws {
        googleRevision += 1
        googleLoadTask?.cancel()
        googleLoadTask = nil
        try GoogleTTSCredentialStore.save(key)
    }
    func deleteGoogle() throws {
        googleRevision += 1
        googleLoadTask?.cancel()
        googleLoadTask = nil
        try GoogleTTSCredentialStore.delete()
    }

    func loadElevenLabs() async -> String {
        let revision = elevenLabsRevision
        if let elevenLabsLoadTask {
            let value = await elevenLabsLoadTask.value
            return elevenLabsRevision == revision ? value : ""
        }
        let task = Task { await ElevenLabsCredentialStore.load() }
        elevenLabsLoadTask = task
        let value = await task.value
        guard elevenLabsRevision == revision else { return "" }
        elevenLabsLoadTask = nil
        return value
    }
    func saveElevenLabs(_ key: String) throws {
        elevenLabsRevision += 1
        elevenLabsLoadTask?.cancel()
        elevenLabsLoadTask = nil
        try ElevenLabsCredentialStore.save(key)
    }
    func deleteElevenLabs() throws {
        elevenLabsRevision += 1
        elevenLabsLoadTask?.cancel()
        elevenLabsLoadTask = nil
        try ElevenLabsCredentialStore.delete()
    }

    func loadMaziao() async -> String {
        let revision = maziaoRevision
        if let maziaoLoadTask {
            let value = await maziaoLoadTask.value
            return maziaoRevision == revision ? value : ""
        }
        let task = Task { await MaziaoCredentialStore.load() }
        maziaoLoadTask = task
        let value = await task.value
        guard maziaoRevision == revision else { return "" }
        maziaoLoadTask = nil
        return value
    }
    func saveMaziao(_ key: String) throws {
        maziaoRevision += 1
        maziaoLoadTask?.cancel()
        maziaoLoadTask = nil
        try MaziaoCredentialStore.save(key)
    }
    func deleteMaziao() throws {
        maziaoRevision += 1
        maziaoLoadTask?.cancel()
        maziaoLoadTask = nil
        try MaziaoCredentialStore.delete()
    }
}

private enum DubbingKeychainStore {
    private static let queue = DispatchQueue(
        label: "com.gemst.media-support-master.dubbing-keychain-read",
        qos: .utility,
        attributes: .concurrent
    )

    static func load(service: String, account: String) async -> String {
        await withCheckedContinuation { continuation in
            let completion = DubbingKeychainLoadCompletion(continuation)
            queue.async {
                completion.resolve(loadBlocking(service: service, account: account))
            }
            queue.asyncAfter(deadline: .now() + 4) {
                completion.resolve("")
            }
        }
    }

    static func contains(service: String, account: String) -> Bool {
        let context = nonInteractiveContext()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private static func loadBlocking(service: String, account: String) -> String {
        let context = nonInteractiveContext()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    static func save(_ key: String, service: String, account: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(service: service, account: account)
            return
        }
        let data = Data(trimmed.utf8)
        let context = nonInteractiveContext()
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw DubbingCredentialError.keychain(addStatus) }
            return
        }
        throw DubbingCredentialError.keychain(updateStatus)
    }

    static func delete(service: String, account: String) throws {
        let context = nonInteractiveContext()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DubbingCredentialError.keychain(status)
        }
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}

private final class DubbingKeychainLoadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?

    init(_ continuation: CheckedContinuation<String, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: String) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: value)
    }
}

enum DubbingCredentialError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Không lưu được khóa TTS trong Keychain (\(status))."
        }
    }
}
