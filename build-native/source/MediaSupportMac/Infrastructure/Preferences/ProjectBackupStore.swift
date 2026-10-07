import Foundation

// MARK: - Models

struct ProjectBackupArtifacts: Codable, Equatable {
    var workingSRT: String?
    var mirroredSRT: String?
    var translatedSRT: String?
    /// Thư mục deliverable: `{parent}/{tên_project}/` — video + srt + xml + txt
    var exportBundleDir: String?
}

struct ProjectBackupProgress: Codable, Equatable {
    var whisperComplete = false
    var translateComplete = false
}

struct ProjectBackupPrefs: Codable, Equatable {
    var targetLang = "vi"
    var sourceLang = "auto"
}

struct ProjectBackupManifest: Codable {
    static let currentVersion = 1

    var version = ProjectBackupManifest.currentVersion
    var id: String
    var mediaPath: String
    var mediaDisplayName: String
    var artifacts: ProjectBackupArtifacts
    var lang: MediaLanguageRecord?
    var progress: ProjectBackupProgress
    var prefs: ProjectBackupPrefs
    var completionSummary: String
    var burnStyle: SubtitleBurnStyle
    var createdAt: Date
    var updatedAt: Date
}

struct ProjectBackupIndex: Codable {
    static let currentVersion = 1

    var version = ProjectBackupIndex.currentVersion
    var projects: [ProjectBackupIndexEntry]
}

struct ProjectBackupIndexEntry: Codable, Identifiable {
    var id: String
    var mediaPath: String
    var displayName: String
    var updatedAt: Date
    var sizeBytes: Int64
}

// MARK: - Store

enum ProjectBackupStore {
    private static let projectsFolder = "projects"
    private static let indexFileName = "index.json"
    private static let manifestFileName = "manifest.json"
    private static let summaryFileName = "summary.txt"
    private static let transcriptFileName = "transcript.srt"
    private static let exportsFolder = "exports"

    // MARK: Paths

    static func backupRoot() -> URL {
        BackupPreferences.shared.backupRootURL
    }

    static func projectsRoot() -> URL {
        backupRoot().appendingPathComponent(projectsFolder, isDirectory: true)
    }

    static func projectID(for media: URL) -> String {
        ProjectBackupPathPolicy.projectID(for: media)
    }

    static func projectDir(for media: URL) -> URL {
        let id = projectID(for: media)
        let slug = ProjectBackupPathPolicy.projectFolderSlug(for: media)
        let named = projectsRoot().appendingPathComponent("\(slug)__\(id)", isDirectory: true)
        migrateLegacyProjectDirIfNeeded(id: id, namedDir: named)
        return named
    }

    private static func migrateLegacyProjectDirIfNeeded(id: String, namedDir: URL) {
        guard !FileManager.default.fileExists(atPath: namedDir.path) else { return }
        let legacy = projectsRoot().appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.moveItem(at: legacy, to: namedDir)
    }

    static func manifestURL(for media: URL) -> URL {
        projectDir(for: media).appendingPathComponent(manifestFileName)
    }

    static func summaryURL(for media: URL) -> URL {
        projectDir(for: media).appendingPathComponent(summaryFileName)
    }

    static func workingSRTURL(for media: URL) -> URL {
        projectDir(for: media).appendingPathComponent(transcriptFileName)
    }

    /// Bản dịch trong vault — không đè `transcript.srt` (gốc Whisper).
    static func translatedSRTURL(for media: URL, targetLang: String) -> URL {
        let lang = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = lang.isEmpty ? "translated" : lang
        return exportsDir(for: media).appendingPathComponent("translated_\(token).srt")
    }

    static func resolvedTranslatedSRTURL(for media: URL, targetLang: String? = nil) -> URL? {
        if let path = load(for: media)?.artifacts.translatedSRT,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let lang = targetLang ?? load(for: media)?.prefs.targetLang ?? "vi"
        let candidate = translatedSRTURL(for: media, targetLang: lang)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static func isVaultOriginalSRT(_ url: URL, media: URL) -> Bool {
        url.standardizedFileURL == workingSRTURL(for: media).standardizedFileURL
    }

    static func exportsDir(for media: URL) -> URL {
        projectDir(for: media).appendingPathComponent(exportsFolder, isDirectory: true)
    }

    static func coLocatedSRT(for media: URL) -> URL {
        coLocatedDeliverableURL(for: media, targetLang: nil, extension: "srt")
    }

    /// Deliverable cạnh file video — cùng thư mục với media (gói `{tên}/` hoặc thư mục gốc).
    static func coLocatedDeliverableURL(for media: URL, targetLang: String?, extension ext: String) -> URL {
        ProjectBackupPathPolicy.coLocatedDeliverableURL(
            for: media,
            targetLang: targetLang,
            extension: ext
        )
    }

    /// Đường dẫn file cạnh video — dùng stem thật của file media, không suy từ bundle name.
    static func packageDeliverableURL(for media: URL, targetLang: String?, extension ext: String) -> URL {
        coLocatedDeliverableURL(for: media, targetLang: targetLang, extension: ext)
    }

    /// Tạo `{cha}/{tên}/`, đưa video vào, ghi file deliverable cạnh video.
    @discardableResult
    static func exportDeliverablePackage(
        _ text: String,
        media: URL,
        targetLang: String? = nil,
        extension ext: String
    ) throws -> URL {
        let packagedMedia = try ensureMediaInExportPackage(media: media)
        let dest = packageDeliverableURL(for: packagedMedia, targetLang: targetLang, extension: ext)

        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: dest, atomically: true, encoding: .utf8)

        guard FileManager.default.fileExists(atPath: dest.path) else {
            throw NSError(
                domain: "ProjectBackupStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Ghi file thất bại: \(dest.path)"]
            )
        }

        if ext == "srt", targetLang == nil {
            var manifest = load(for: packagedMedia) ?? freshManifest(for: packagedMedia)
            manifest.artifacts.mirroredSRT = dest.path
            manifest.artifacts.workingSRT = workingSRTURL(for: packagedMedia).path
            writeManifest(manifest, media: packagedMedia)
        }

        recordExportBundleDir(for: packagedMedia)
        return dest
    }

    /// Ghi deliverable — alias gói `{tên}/` (video + file).
    @discardableResult
    static func publishTextDeliverable(
        _ text: String,
        media: URL,
        targetLang: String? = nil,
        extension ext: String
    ) throws -> URL {
        try exportDeliverablePackage(text, media: media, targetLang: targetLang, extension: ext)
    }

    /// Tạo thư mục gói, di chuyển (hoặc copy) video vào — trả path video trong gói.
    @discardableResult
    static func ensureMediaInExportPackage(media: URL) throws -> URL {
        do {
            return try syncMediaIntoBundle(media: media)
        } catch {
            ensureExportBundle(for: media)
            let dest = bundleMediaURL(for: media)
            if FileManager.default.fileExists(atPath: dest.path) {
                recordExportBundleDir(for: media)
                return dest
            }
            try FileManager.default.copyItem(at: media, to: dest)
            recordExportBundleDir(for: media)
            return dest
        }
    }

    @discardableResult
    static func publishFileDeliverable(
        from source: URL,
        media: URL,
        targetLang: String? = nil,
        extension ext: String
    ) throws -> URL {
        let text = try String(contentsOf: source, encoding: .utf8)
        return try publishTextDeliverable(text, media: media, targetLang: targetLang, extension: ext)
    }

    /// `{thư_mục_gốc}/{tên_video}/` — gói deliverable cạnh file media.
    static func exportBundleDir(for media: URL) -> URL {
        ProjectBackupPathPolicy.exportBundleDir(for: media)
    }

    static func resolvedExportBundleDir(for media: URL) -> URL? {
        if let path = load(for: media)?.artifacts.exportBundleDir,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let dir = exportBundleDir(for: media)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func bundleMediaURL(for media: URL) -> URL {
        ProjectBackupPathPolicy.bundleMediaURL(for: media)
    }

    static func bundleDeliverableURL(for media: URL, extension ext: String) -> URL {
        coLocatedDeliverableURL(for: media, targetLang: nil, extension: ext)
    }

    @discardableResult
    static func ensureExportBundle(for media: URL) -> URL {
        let dir = exportBundleDir(for: media)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Di chuyển video gốc vào bundle `{tên}/` — không copy để tránh trùng file ngoài thư mục.
    @discardableResult
    static func syncMediaIntoBundle(media: URL) throws -> URL {
        let bundle = ensureExportBundle(for: media).standardizedFileURL
        let source = media.standardizedFileURL
        if source.deletingLastPathComponent() == bundle {
            recordExportBundleDir(for: media)
            return source
        }

        reconcileCoLocatedFiles(for: source)

        let dest = bundleMediaURL(for: media)
        let parentDir = source.deletingLastPathComponent()
        let baseName = ProjectBackupPathPolicy.projectBundleName(for: source)

        if FileManager.default.fileExists(atPath: dest.path) {
            let srcSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let dstSize = try dest.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if srcSize == dstSize {
                try FileManager.default.removeItem(at: source)
                cleanupSiblingDeliverables(near: parentDir, baseName: baseName)
                migrateProjectMediaPath(from: source, to: dest)
                recordExportBundleDir(for: dest)
                return dest
            }
            try FileManager.default.removeItem(at: dest)
        }

        try FileManager.default.moveItem(at: source, to: dest)
        cleanupSiblingDeliverables(near: parentDir, baseName: baseName)
        migrateProjectMediaPath(from: source, to: dest)
        recordExportBundleDir(for: dest)
        return dest
    }

    /// Sau khi media chuyển path — migrate vault backup + cập nhật manifest/index.
    static func migrateProjectMediaPath(from oldMedia: URL, to newMedia: URL) {
        let oldID = projectID(for: oldMedia)
        let newID = projectID(for: newMedia)
        let oldDir = projectDir(for: oldMedia)
        let newDir = projectDir(for: newMedia)
        let oldManifestURL = oldDir.appendingPathComponent(manifestFileName)

        var manifest: ProjectBackupManifest?
        if FileManager.default.fileExists(atPath: oldManifestURL.path),
           let data = try? Data(contentsOf: oldManifestURL),
           let decoded = try? JSONDecoder().decode(ProjectBackupManifest.self, from: data) {
            manifest = decoded
        }

        if oldID != newID, FileManager.default.fileExists(atPath: oldDir.path) {
            if FileManager.default.fileExists(atPath: newDir.path) {
                try? FileManager.default.removeItem(at: newDir)
            }
            try? FileManager.default.moveItem(at: oldDir, to: newDir)
        } else if !FileManager.default.fileExists(atPath: newDir.path) {
            try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        }

        if var manifest {
            manifest.id = newID
            manifest.mediaPath = newMedia.path
            manifest.mediaDisplayName = newMedia.lastPathComponent
            manifest.artifacts.exportBundleDir = exportBundleDir(for: newMedia).path
            manifest.updatedAt = Date()
            writeManifest(manifest, media: newMedia)
        }

        updateIndex()
    }

    @discardableResult
    static func writeSRTToBundle(from workingSRT: URL, media: URL) throws -> URL {
        ensureExportBundle(for: media)
        let dest = bundleDeliverableURL(for: media, extension: "srt")
        if workingSRT.standardizedFileURL != dest.standardizedFileURL {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: workingSRT, to: dest)
        }
        recordExportBundleDir(for: media)
        return dest
    }

    @discardableResult
    static func writeTXTToBundle(_ text: String, media: URL) throws -> URL {
        ensureExportBundle(for: media)
        let dest = bundleDeliverableURL(for: media, extension: "txt")
        try text.write(to: dest, atomically: true, encoding: .utf8)
        recordExportBundleDir(for: media)
        return dest
    }

    /// TXT bản dịch trong bundle: `{tên}_{lang}.txt`
    @discardableResult
    static func writeTranslatedTXTToBundle(_ text: String, media: URL, targetLang: String) throws -> URL {
        ensureExportBundle(for: media)
        let dest = bundleTranslatedDeliverableURL(for: media, targetLang: targetLang, extension: "txt")
        try text.write(to: dest, atomically: true, encoding: .utf8)
        recordExportBundleDir(for: media)
        return dest
    }

    static func bundleTranslatedDeliverableURL(for media: URL, targetLang: String, extension ext: String) -> URL {
        coLocatedDeliverableURL(for: media, targetLang: targetLang, extension: ext)
    }

    // MARK: Layout

    static func ensureLayout() {
        let root = backupRoot()
        try? FileManager.default.createDirectory(at: projectsRoot(), withIntermediateDirectories: true)
        // Quy hoạch: vault/projects (metadata) tách khỏi deliverable cạnh file gốc.
        let readme = root.appendingPathComponent("LOU_TRUC.txt")
        guard !FileManager.default.fileExists(atPath: readme.path) else { return }
        let text = """
        Media Support Master — thư mục backup

        projects/     Vault dự án (SRT làm việc, manifest, tóm tắt)
                      Tên thư mục: {tên_video}__{mã_ngắn}

        index.json    Danh mục dự án (app tự quản lý)

        Gói xuất (video + SRT + TXT…) nằm cạnh file media gốc:
        {thư_mục_cha}/{tên_video}/
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func ensureProjectDir(for media: URL) -> URL {
        ensureLayout()
        let dir = projectDir(for: media)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: exportsDir(for: media), withIntermediateDirectories: true)
        return dir
    }

    // MARK: Public API

    static func hasBackup(for media: URL) -> Bool {
        if FileManager.default.fileExists(atPath: manifestURL(for: media).path) {
            return true
        }
        return legacySessionURL(for: media) != nil
    }

    static func load(for media: URL) -> ProjectBackupManifest? {
        migrateLegacyIfNeeded(for: media)

        let url = manifestURL(for: media)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var manifest = try? JSONDecoder().decode(ProjectBackupManifest.self, from: data),
              manifest.mediaPath == media.path
        else { return nil }

        manifest = hydrateLanguageIfNeeded(manifest, media: media)
        return manifest
    }

    static func loadSummary(for media: URL) -> String {
        let url = summaryURL(for: media)
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func languageRecord(for media: URL) -> MediaLanguageRecord? {
        if let manifest = load(for: media), let lang = manifest.lang {
            return lang
        }
        return MediaLanguageRecord.load(near: media)
    }

    static func save(
        media: URL,
        srtURL: URL?,
        targetLang: String,
        sourceLang: String,
        whisperComplete: Bool,
        translateComplete: Bool,
        completionSummary: String,
        transcriptSummary: String,
        burnStyle: SubtitleBurnStyle
    ) {
        ensureProjectDir(for: media)
        let id = projectID(for: media)
        let now = Date()

        var manifest = load(for: media) ?? ProjectBackupManifest(
            id: id,
            mediaPath: media.path,
            mediaDisplayName: media.lastPathComponent,
            artifacts: ProjectBackupArtifacts(),
            lang: MediaLanguageRecord.load(near: media),
            progress: ProjectBackupProgress(),
            prefs: ProjectBackupPrefs(),
            completionSummary: "",
            burnStyle: burnStyle,
            createdAt: now,
            updatedAt: now
        )

        manifest.mediaPath = media.path
        manifest.mediaDisplayName = media.lastPathComponent
        manifest.prefs.targetLang = targetLang
        manifest.prefs.sourceLang = sourceLang
        manifest.progress.whisperComplete = whisperComplete
        manifest.progress.translateComplete = translateComplete
        manifest.completionSummary = completionSummary
        manifest.burnStyle = burnStyle
        manifest.updatedAt = now
        manifest.lang = absorbLanguageSidecar(for: media) ?? manifest.lang

        if let srtURL, FileManager.default.fileExists(atPath: srtURL.path) {
            if translateComplete, !isVaultOriginalSRT(srtURL, media: media) {
                if let translated = resolvedTranslatedSRTURL(for: media, targetLang: targetLang) {
                    manifest.artifacts.translatedSRT = translated.path
                } else {
                    try? ingestTranslatedTranscript(from: srtURL, media: media, targetLang: targetLang)
                    manifest.artifacts.translatedSRT = translatedSRTURL(for: media, targetLang: targetLang).path
                }
            } else {
                syncWorkingTranscript(from: srtURL, media: media, manifest: &manifest)
            }
        } else if translateComplete,
                  let translated = resolvedTranslatedSRTURL(for: media, targetLang: targetLang) {
            manifest.artifacts.translatedSRT = translated.path
        }

        writeSummary(transcriptSummary, media: media)
        writeManifest(manifest, media: media)
        finalizeCoLocatedCleanup(media: media)
        updateIndex()
    }

    static func clearTranslatedTranscript(for media: URL) {
        guard var manifest = load(for: media) else { return }
        if let path = manifest.artifacts.translatedSRT {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        manifest.artifacts.translatedSRT = nil
        manifest.progress.translateComplete = false
        manifest.updatedAt = Date()
        writeManifest(manifest, media: media)
    }

    static func ingestTranslatedTranscript(from source: URL, media: URL, targetLang: String) throws {
        ensureProjectDir(for: media)
        try FileManager.default.createDirectory(at: exportsDir(for: media), withIntermediateDirectories: true)
        let dest = translatedSRTURL(for: media, targetLang: targetLang)
        if source.standardizedFileURL != dest.standardizedFileURL {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        }

        var manifest = load(for: media) ?? freshManifest(for: media)
        manifest.artifacts.translatedSRT = dest.path
        manifest.progress.translateComplete = true
        manifest.updatedAt = Date()
        writeManifest(manifest, media: media)
        updateIndex()
    }

    static func ingestTranscript(from source: URL, media: URL) throws {
        ensureProjectDir(for: media)
        let dest = workingSRTURL(for: media)
        if source.standardizedFileURL != dest.standardizedFileURL {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        }

        var manifest = load(for: media) ?? freshManifest(for: media)
        manifest.artifacts.workingSRT = dest.path
        manifest.lang = absorbLanguageSidecar(for: media) ?? manifest.lang
        manifest.updatedAt = Date()
        writeManifest(manifest, media: media)

        finalizeCoLocatedCleanup(media: media)
        updateIndex()
    }

    /// Gom `.srt` / `.msm-lang.json` cạnh media vào vault (mở lại video cũ).
    static func reconcileCoLocatedFiles(for media: URL) {
        let srt = coLocatedSRT(for: media)
        let lang = MediaLanguageRecord.sidecarURL(for: media)
        let hasSRT = FileManager.default.fileExists(atPath: srt.path)
        let hasLang = FileManager.default.fileExists(atPath: lang.path)
        guard hasSRT || hasLang else { return }

        if hasSRT {
            try? ingestTranscript(from: srt, media: media)
        } else if hasLang {
            var manifest = load(for: media) ?? freshManifest(for: media)
            manifest.lang = absorbLanguageSidecar(for: media) ?? manifest.lang
            manifest.updatedAt = Date()
            writeManifest(manifest, media: media)
            finalizeCoLocatedCleanup(media: media)
            updateIndex()
        }
    }

    static func resolvedSRTURL(for media: URL) -> URL? {
        migrateLegacyIfNeeded(for: media)
        let working = workingSRTURL(for: media)
        if FileManager.default.fileExists(atPath: working.path) {
            return working
        }
        if BackupPreferences.shared.mirrorSRTBesideMedia {
            let mirrored = coLocatedSRT(for: media)
            if FileManager.default.fileExists(atPath: mirrored.path) {
                return mirrored
            }
        }
        if let path = load(for: media)?.artifacts.workingSRT,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func burnOutputURL(for media: URL) -> URL {
        let base = media.deletingPathExtension().lastPathComponent
        let ext = media.pathExtension
        if BackupPreferences.shared.mirrorSubbedBesideMedia {
            return media.deletingLastPathComponent()
                .appendingPathComponent("\(base)_subbed.\(ext)")
        }
        ensureProjectDir(for: media)
        return exportsDir(for: media).appendingPathComponent("\(base)_subbed.\(ext)")
    }

    static func deleteBackup(for media: URL) {
        let dir = projectDir(for: media)
        try? FileManager.default.removeItem(at: dir)
        updateIndex()
    }

    static func purgeAll() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot(),
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.hasDirectoryPath {
            try? FileManager.default.removeItem(at: entry)
        }
        updateIndex()
    }

    static func purgeStale(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for entry in listIndexEntries() where entry.updatedAt < cutoff {
            deleteBackup(for: URL(fileURLWithPath: entry.mediaPath))
        }
    }

    static func estimatedTotalSize() -> Int64 {
        listIndexEntries().reduce(0) { $0 + $1.sizeBytes }
    }

    static func listIndexEntries() -> [ProjectBackupIndexEntry] {
        (try? loadIndex())?.projects.sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    static func projectSize(for media: URL) -> Int64 {
        directorySize(projectDir(for: media))
    }

    static func applyRetentionPolicy() {
        let days = BackupPreferences.shared.retentionDays
        guard days > 0 else { return }
        purgeStale(olderThan: days)
    }

    // MARK: Private

    private static func freshManifest(for media: URL) -> ProjectBackupManifest {
        let now = Date()
        return ProjectBackupManifest(
            id: projectID(for: media),
            mediaPath: media.path,
            mediaDisplayName: media.lastPathComponent,
            artifacts: ProjectBackupArtifacts(),
            lang: MediaLanguageRecord.load(near: media),
            progress: ProjectBackupProgress(),
            prefs: ProjectBackupPrefs(),
            completionSummary: "",
            burnStyle: SubtitleBurnStyle.load(),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func writeManifest(_ manifest: ProjectBackupManifest, media: URL) {
        let url = manifestURL(for: media)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func writeSummary(_ text: String, media: URL) {
        let url = summaryURL(for: media)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func syncWorkingTranscript(
        from source: URL,
        media: URL,
        manifest: inout ProjectBackupManifest
    ) {
        let dest = workingSRTURL(for: media)
        do {
            if source.standardizedFileURL != dest.standardizedFileURL {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
            }
            manifest.artifacts.workingSRT = dest.path
            writeManifest(manifest, media: media)
            finalizeCoLocatedCleanup(media: media)
        } catch {
            manifest.artifacts.workingSRT = source.path
        }
    }

    private static func mirrorSRTToMediaIfNeeded(media: URL, manifest: ProjectBackupManifest) {
        guard BackupPreferences.shared.mirrorSRTBesideMedia else { return }
        guard let working = manifest.artifacts.workingSRT,
              FileManager.default.fileExists(atPath: working)
        else { return }

        let mirror = coLocatedSRT(for: media)
        do {
            if FileManager.default.fileExists(atPath: mirror.path) {
                try FileManager.default.removeItem(at: mirror)
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: working), to: mirror)
        } catch {
            return
        }

        var updated = manifest
        updated.artifacts.mirroredSRT = mirror.path
        writeManifest(updated, media: media)
    }

    /// Lang luôn vào manifest; `.msm-lang.json` luôn xóa.
    /// SRT cạnh video: giữ deliverable trong gói `{tên}/`; chỉ xóa file lẻ ngoài bundle khi tắt mirror.
    private static func finalizeCoLocatedCleanup(media: URL) {
        try? FileManager.default.removeItem(at: MediaLanguageRecord.sidecarURL(for: media))
        if let session = legacySessionURL(for: media) {
            try? FileManager.default.removeItem(at: session)
        }

        guard let manifest = load(for: media) else { return }
        let bundleDir = exportBundleDir(for: media).standardizedFileURL
        let mediaInBundle = media.deletingLastPathComponent().standardizedFileURL == bundleDir

        if BackupPreferences.shared.mirrorSRTBesideMedia {
            mirrorSRTToMediaIfNeeded(media: media, manifest: manifest)
        } else if mediaInBundle {
            let deliverable = coLocatedSRT(for: media)
            if FileManager.default.fileExists(atPath: deliverable.path) {
                var updated = manifest
                updated.artifacts.mirroredSRT = deliverable.path
                writeManifest(updated, media: media)
            }
        } else {
            try? FileManager.default.removeItem(at: coLocatedSRT(for: media))
            var updated = manifest
            updated.artifacts.mirroredSRT = nil
            writeManifest(updated, media: media)
        }
    }

    /// Xóa `.srt` / sidecar cạnh file gốc sau khi đã gom vào bundle/vault.
    private static func cleanupSiblingDeliverables(near parentDir: URL, baseName: String) {
        try? FileManager.default.removeItem(at: parentDir.appendingPathComponent("\(baseName).srt"))
        try? FileManager.default.removeItem(at: MediaLanguageRecord.sidecarURL(
            for: parentDir.appendingPathComponent("\(baseName).mp4")
        ))
        let session = parentDir
            .appendingPathComponent(baseName)
            .appendingPathExtension("msm-session")
            .appendingPathExtension("json")
        try? FileManager.default.removeItem(at: session)
    }

    private static func absorbLanguageSidecar(for media: URL) -> MediaLanguageRecord? {
        guard let record = MediaLanguageRecord.load(near: media) else { return nil }
        try? FileManager.default.removeItem(at: MediaLanguageRecord.sidecarURL(for: media))
        return record
    }

    static func exportSRTBesideMedia(from workingSRT: URL, media: URL) throws -> URL {
        try syncMediaIntoBundle(media: media)
        if FileManager.default.fileExists(atPath: workingSRT.path) {
            return try publishFileDeliverable(from: workingSRT, media: media, extension: "srt")
        }
        return try writeSRTToBundle(from: workingSRT, media: media)
    }

    /// Xuất thêm bản dịch vào bundle deliverable: `{tên}_{lang}.srt`
    static func exportTranslatedSRTToBundle(from translatedSRT: URL, media: URL, targetLang: String) throws -> URL {
        try syncMediaIntoBundle(media: media)
        let dest = bundleTranslatedDeliverableURL(for: media, targetLang: targetLang, extension: "srt")
        if translatedSRT.standardizedFileURL != dest.standardizedFileURL {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: translatedSRT, to: dest)
        }
        recordExportBundleDir(for: media)
        return dest
    }

    private static func recordExportBundleDir(for media: URL) {
        let path = exportBundleDir(for: media).path
        guard var manifest = load(for: media) else {
            var fresh = freshManifest(for: media)
            fresh.artifacts.exportBundleDir = path
            writeManifest(fresh, media: media)
            updateIndex()
            return
        }
        manifest.artifacts.exportBundleDir = path
        manifest.updatedAt = Date()
        writeManifest(manifest, media: media)
        updateIndex()
    }

    private static func hydrateLanguageIfNeeded(
        _ manifest: ProjectBackupManifest,
        media: URL
    ) -> ProjectBackupManifest {
        var copy = manifest
        if copy.lang == nil {
            copy.lang = MediaLanguageRecord.load(near: media)
        }
        return copy
    }

    private static func loadIndex() throws -> ProjectBackupIndex {
        let url = backupRoot().appendingPathComponent(indexFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectBackupIndex(projects: [])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectBackupIndex.self, from: data)
    }

    private static func updateIndex() {
        ensureLayout()
        var entries: [ProjectBackupIndexEntry] = []
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            writeIndex(ProjectBackupIndex(projects: []))
            return
        }

        for dir in dirs where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent(manifestFileName)
            guard FileManager.default.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(ProjectBackupManifest.self, from: data)
            else { continue }

            entries.append(
                ProjectBackupIndexEntry(
                    id: manifest.id,
                    mediaPath: manifest.mediaPath,
                    displayName: manifest.mediaDisplayName,
                    updatedAt: manifest.updatedAt,
                    sizeBytes: directorySize(dir)
                )
            )
        }

        entries.sort { $0.updatedAt > $1.updatedAt }
        writeIndex(ProjectBackupIndex(projects: entries))
    }

    private static func writeIndex(_ index: ProjectBackupIndex) {
        let url = backupRoot().appendingPathComponent(indexFileName)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: Legacy migration

    private struct LegacySubtitleProjectSession: Codable {
        var mediaPath: String
        var srtPath: String?
        var targetLang: String
        var sourceLang: String
        var whisperComplete: Bool
        var translateComplete: Bool
        var completionSummary: String
        var transcriptSummary: String
        var burnStyle: SubtitleBurnStyle
        var updatedAt: Date
    }

    private static func legacySessionURL(for media: URL) -> URL? {
        let url = media.deletingPathExtension()
            .appendingPathExtension("msm-session")
            .appendingPathExtension("json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func migrateLegacyIfNeeded(for media: URL) {
        guard !FileManager.default.fileExists(atPath: manifestURL(for: media).path),
              let legacyURL = legacySessionURL(for: media),
              let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode(LegacySubtitleProjectSession.self, from: data),
              legacy.mediaPath == media.path
        else { return }

        ensureProjectDir(for: media)
        let now = Date()
        var manifest = ProjectBackupManifest(
            id: projectID(for: media),
            mediaPath: media.path,
            mediaDisplayName: media.lastPathComponent,
            artifacts: ProjectBackupArtifacts(
                workingSRT: legacy.srtPath,
                mirroredSRT: BackupPreferences.shared.mirrorSRTBesideMedia ? legacy.srtPath : nil,
                translatedSRT: nil
            ),
            lang: MediaLanguageRecord.load(near: media),
            progress: ProjectBackupProgress(
                whisperComplete: legacy.whisperComplete,
                translateComplete: legacy.translateComplete
            ),
            prefs: ProjectBackupPrefs(
                targetLang: legacy.targetLang,
                sourceLang: legacy.sourceLang
            ),
            completionSummary: legacy.completionSummary,
            burnStyle: legacy.burnStyle,
            createdAt: legacy.updatedAt,
            updatedAt: now
        )

        if let srtPath = legacy.srtPath, FileManager.default.fileExists(atPath: srtPath) {
            try? ingestTranscript(from: URL(fileURLWithPath: srtPath), media: media)
            if let reloaded = load(for: media) {
                manifest = reloaded
            }
        }

        writeSummary(legacy.transcriptSummary, media: media)
        manifest.updatedAt = now
        writeManifest(manifest, media: media)
        try? FileManager.default.removeItem(at: legacyURL)
        updateIndex()
    }
}
