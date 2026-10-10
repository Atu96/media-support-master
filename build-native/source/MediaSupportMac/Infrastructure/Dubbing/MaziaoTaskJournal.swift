import CryptoKit
import Foundation

/// Stores only opaque receipts and digests. Never persists text, keys or signed audio URLs.
struct MaziaoTaskJournal: Sendable {
    struct Receipt: Codable, Sendable, Equatable {
        let accountDigest: String
        let taskID: String
        let partDigests: [String]
        let createdAt: Date
        var characterCount: Int? = nil

        func indices(for parts: [String]) -> [Int]? {
            var used = Set<Int>()
            var result: [Int] = []
            for part in parts {
                guard let index = partDigests.indices.first(where: {
                    partDigests[$0] == part && !used.contains($0)
                }) else { return nil }
                used.insert(index)
                result.append(index)
            }
            return result
        }
    }

    let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gemst.media-support-master")
            .appendingPathComponent("MaziaoPendingTasks", isDirectory: true)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func partDigest(_ request: DubbingSpeechRequest) -> String {
        let fields = [request.text, request.localeIdentifier, request.voiceIdentifier ?? "",
                      request.modelIdentifier, String(request.rate)]
        return digest((try? JSONEncoder().encode(fields)) ?? Data())
    }

    func matching(account: String, parts: [String]) throws -> Receipt? {
        guard !parts.isEmpty, FileManager.default.fileExists(atPath: rootURL.path) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        var matches: [Receipt] = []
        for url in files where url.pathExtension == "json" {
            // Corrupt journals fail closed: do not unknowingly submit another paid job.
            let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: url))
            if receipt.accountDigest == account, receipt.indices(for: parts) != nil { matches.append(receipt) }
        }
        return matches.sorted { $0.createdAt < $1.createdAt }.first
    }

    func save(_ receipt: Receipt) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(receipt).write(to: url(for: receipt), options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(for: receipt).path)
    }

    func remove(_ receipt: Receipt) throws {
        let path = url(for: receipt)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    private func url(for receipt: Receipt) -> URL {
        rootURL.appendingPathComponent(Self.digest(Data((receipt.accountDigest + receipt.taskID).utf8)) + ".json")
    }
}

@MainActor
enum MaziaoTaskRecovery {
    /// A fresh process reads the same journal. Network errors/cancellation keep the receipt.
    static func resolve(
        journal: MaziaoTaskJournal,
        account: String,
        parts: [String],
        characterCount: Int = 0,
        onResume: () async -> Void = {},
        submit: () async throws -> String,
        wait: (MaziaoTaskJournal.Receipt) async throws -> [URL]
    ) async throws -> [URL] {
        var receipt = try journal.matching(account: account, parts: parts)
        if receipt == nil {
            try Task.checkCancellation()
            let taskID = try await submit()
            receipt = .init(accountDigest: account, taskID: taskID, partDigests: parts, createdAt: Date(),
                            characterCount: characterCount)
            // Persist immediately, including when cancellation arrived during submit.
            try journal.save(receipt!)
        } else {
            await onResume()
        }
        guard let receipt, let indices = receipt.indices(for: parts) else {
            throw DubbingError.invalidAudioBuffer
        }
        try Task.checkCancellation()
        let urls = try await wait(receipt)
        guard urls.count == receipt.partDigests.count else { throw DubbingError.invalidAudioBuffer }
        return indices.map { urls[$0] }
    }
}
