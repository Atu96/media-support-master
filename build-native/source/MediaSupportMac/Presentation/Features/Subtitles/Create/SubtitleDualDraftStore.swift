import Foundation

/// Dual draft cho 2 tab Tạo sub — UserDefaults + recent lists.
/// Xem `BUILD-EXPERIENCE.md` §17. Không gộp `mediaURL` chung cho cả hai draft.
@MainActor
enum SubtitleDualDraftStore {
    static let lastMediaPathKey = "msm.lastMediaPath"
    static let whisperDraftPathKey = "msm.whisperDraftPath"
    static let scriptDraftPathKey = "msm.scriptDraftPath"
    static let whisperRecentDraftsKey = "msm.whisperRecentDrafts"
    static let scriptRecentDraftsKey = "msm.scriptRecentDrafts"

    // MARK: - Restore

    static func restoreDraftURLs() -> (whisper: URL?, script: URL?) {
        let whisper = existingURL(forKey: whisperDraftPathKey)
        let script = existingURL(forKey: scriptDraftPathKey)
        return (whisper, script)
    }

    private static func existingURL(forKey key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Set draft

    static func setWhisperDraft(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: whisperDraftPathKey)
        recordRecentDraft(path: url.path, key: whisperRecentDraftsKey)
    }

    static func setScriptDraft(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: scriptDraftPathKey)
        recordRecentDraft(path: url.path, key: scriptRecentDraftsKey)
    }

    static func clearWhisperDraftPath() {
        UserDefaults.standard.removeObject(forKey: whisperDraftPathKey)
    }

    static func clearScriptDraftPath() {
        UserDefaults.standard.removeObject(forKey: scriptDraftPathKey)
    }

    // MARK: - Recent

    static func recordRecentDraft(path: String, key: String) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 12 {
            paths = Array(paths.prefix(12))
        }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func removeRecentDraft(path: String, key: String) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func removeFromBothRecentLists(path: String) {
        removeRecentDraft(path: path, key: whisperRecentDraftsKey)
        removeRecentDraft(path: path, key: scriptRecentDraftsKey)
    }

    static func migrateRecentDraftPath(from oldPath: String, to newPath: String, key: String) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths = paths.map { $0 == oldPath ? newPath : $0 }
        var seen = Set<String>()
        paths = paths.filter { seen.insert($0).inserted }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func recentCreateTabEntries(for tab: SubtitleModuleTab, limit: Int = 8) -> [ProjectBackupIndexEntry] {
        let draftKey: String
        switch tab {
        case .create: draftKey = whisperRecentDraftsKey
        case .script: draftKey = scriptRecentDraftsKey
        }

        let draftPaths = (UserDefaults.standard.stringArray(forKey: draftKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }

        let backupByPath = Dictionary(
            uniqueKeysWithValues: ProjectBackupStore.listIndexEntries().map { ($0.mediaPath, $0) }
        )

        var entries: [ProjectBackupIndexEntry] = []
        var seen = Set<String>()

        for path in draftPaths {
            guard seen.insert(path).inserted else { continue }
            if let backup = backupByPath[path] {
                entries.append(backup)
            } else {
                entries.append(recentDraftEntry(for: path))
            }
        }

        for backup in ProjectBackupStore.listIndexEntries()
            .filter({ FileManager.default.fileExists(atPath: $0.mediaPath) })
            .sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard seen.insert(backup.mediaPath).inserted else { continue }
            entries.append(backup)
            if entries.count >= limit { break }
        }

        return Array(entries.prefix(limit))
    }

    private static func recentDraftEntry(for path: String) -> ProjectBackupIndexEntry {
        let url = URL(fileURLWithPath: path)
        let updated = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return ProjectBackupIndexEntry(
            id: "draft-\(path.hashValue)",
            mediaPath: path,
            displayName: url.lastPathComponent,
            updatedAt: updated,
            sizeBytes: 0
        )
    }

    // MARK: - Preview URL for tab

    static func draftURL(for tab: SubtitleModuleTab, whisper: URL?, script: URL?) -> URL? {
        switch tab {
        case .create: return whisper
        case .script: return script
        }
    }

    // MARK: - Relocate after export bundle

    static func adoptRelocatedDraftPaths(
        old: URL,
        new: URL,
        whisperDraft: inout URL?,
        scriptDraft: inout URL?
    ) {
        guard old.standardizedFileURL != new.standardizedFileURL else { return }
        let oldPath = old.path
        let newPath = new.path

        if whisperDraft?.standardizedFileURL == old.standardizedFileURL {
            whisperDraft = new
            UserDefaults.standard.set(newPath, forKey: whisperDraftPathKey)
            migrateRecentDraftPath(from: oldPath, to: newPath, key: whisperRecentDraftsKey)
        }
        if scriptDraft?.standardizedFileURL == old.standardizedFileURL {
            scriptDraft = new
            UserDefaults.standard.set(newPath, forKey: scriptDraftPathKey)
            migrateRecentDraftPath(from: oldPath, to: newPath, key: scriptRecentDraftsKey)
        }
    }
}
