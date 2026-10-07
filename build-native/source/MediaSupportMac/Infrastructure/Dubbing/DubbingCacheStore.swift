import AVFoundation
import Foundation

struct DubbingCacheUsage: Equatable, Sendable {
    let allocatedBytes: Int64
    let clipCount: Int
    let storedFileCount: Int

    static let empty = DubbingCacheUsage(allocatedBytes: 0, clipCount: 0, storedFileCount: 0)
}

struct DubbingCacheStore: Sendable {
    let rootURL: URL

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.gemst.media-support-master") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("DubbingCache", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func clipURL(for fingerprint: String) -> URL {
        rootURL.appendingPathComponent("\(fingerprint).caf")
    }

    func mergedClipURL(for fingerprint: String) -> URL {
        rootURL.appendingPathComponent("\(fingerprint).m4a")
    }

    func existingClipURL(for fingerprint: String) -> URL? {
        let candidates = [clipURL(for: fingerprint), mergedClipURL(for: fingerprint)]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func temporaryMergedClipURL() throws -> URL {
        try prepare()
        return rootURL.appendingPathComponent("merge-\(UUID().uuidString).partial.m4a")
    }

    func commitMergedClip(from temporaryURL: URL, for fingerprint: String) throws -> URL {
        try prepare()
        removeClip(for: fingerprint)
        let destination = mergedClipURL(for: fingerprint)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func aliasClip(from sourceURL: URL, for fingerprint: String) throws -> URL {
        try prepare()
        if let existing = existingClipURL(for: fingerprint) { return existing }
        let destination = sourceURL.pathExtension.lowercased() == "m4a"
            ? mergedClipURL(for: fingerprint)
            : clipURL(for: fingerprint)
        guard sourceURL.standardizedFileURL != destination.standardizedFileURL else { return sourceURL }
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destination)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
        return destination
    }

    func migrateClip(from oldFingerprint: String, to newFingerprint: String) throws -> URL? {
        if let existing = existingClipURL(for: newFingerprint) { return existing }
        guard let oldURL = existingClipURL(for: oldFingerprint) else { return nil }
        try prepare()
        let newURL = clipURL(for: newFingerprint)
        try FileManager.default.copyItem(at: oldURL, to: newURL)
        return newURL
    }

    func removeClip(for fingerprint: String) {
        try? FileManager.default.removeItem(at: clipURL(for: fingerprint))
        try? FileManager.default.removeItem(at: mergedClipURL(for: fingerprint))
    }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try FileManager.default.removeItem(at: rootURL)
    }

    /// Counts actual allocated blocks and de-duplicates hard-linked aliases,
    /// so the number shown in UI reflects disk use instead of logical sizes.
    func usage() throws -> DubbingCacheUsage {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return .empty }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else { return .empty }

        var allocatedBytes: Int64 = 0
        var clipCount = 0
        var storedFileCount = 0
        var seenFileNumbers: Set<UInt64> = []
        for case let url as URL in enumerator {
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == "caf" || fileExtension == "m4a",
                  !url.lastPathComponent.contains(".partial.") else { continue }
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
            ])
            guard values.isRegularFile == true else { continue }
            clipCount += 1

            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let number = attributes[.systemFileNumber] as? NSNumber {
                guard seenFileNumbers.insert(number.uint64Value).inserted else { continue }
            }
            storedFileCount += 1
            let bytes = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? (attributes[.size] as? NSNumber)?.intValue
                ?? 0
            allocatedBytes += Int64(max(0, bytes))
        }
        return DubbingCacheUsage(
            allocatedBytes: allocatedBytes,
            clipCount: clipCount,
            storedFileCount: storedFileCount
        )
    }

    static func audioDuration(at url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}
