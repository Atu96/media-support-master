import Foundation

// MARK: - Session / draft / vault / nạp SRT

extension SubtitleViewModel {
    func adoptRelocatedMediaIfNeeded(from old: URL, to new: URL) {
        guard old.standardizedFileURL != new.standardizedFileURL else { return }
        SubtitleDualDraftStore.adoptRelocatedDraftPaths(
            old: old,
            new: new,
            whisperDraft: &whisperDraftMediaURL,
            scriptDraft: &scriptDraftMediaURL
        )
        UserDefaults.standard.set(new.path, forKey: SubtitleDualDraftStore.lastMediaPathKey)
        mediaURL = new
        refreshSRTURLAfterMediaRelocate(to: new)
        attachPreviewVideo()
    }

    func refreshSRTURLAfterMediaRelocate(to media: URL) {
        if activeTranscriptVariant == .translated,
           let translated = ProjectBackupStore.resolvedTranslatedSRTURL(for: media, targetLang: targetLang),
           FileManager.default.fileExists(atPath: translated.path) {
            srtURL = translated
            return
        }
        if let working = ProjectBackupStore.resolvedSRTURL(for: media) {
            srtURL = working
        }
    }

    func restoreLastSessionIfNeeded() {
        let drafts = SubtitleDualDraftStore.restoreDraftURLs()
        if whisperDraftMediaURL == nil { whisperDraftMediaURL = drafts.whisper }
        if scriptDraftMediaURL == nil { scriptDraftMediaURL = drafts.script }

        guard mediaURL == nil,
              let path = UserDefaults.standard.string(forKey: SubtitleDualDraftStore.lastMediaPathKey),
              FileManager.default.fileExists(atPath: path)
        else { return }
        setMediaURL(URL(fileURLWithPath: path))
    }

    func setWhisperDraftMedia(_ url: URL) {
        whisperDraftMediaURL = url
        SubtitleDualDraftStore.setWhisperDraft(url)
    }

    /// A complete OCR transcript already exists in the vault; do not reload an older sibling SRT.
    func adoptMediaForOCRTranscript(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: SubtitleDualDraftStore.lastMediaPathKey)
        setWhisperDraftMedia(url)
        mediaURL = url
        sessionRestored = false
        exportMessage = ""
        burnMessage = ""
    }

    func setScriptDraftMedia(_ url: URL) {
        scriptDraftMediaURL = url
        SubtitleDualDraftStore.setScriptDraft(url)
    }

    func recentCreateTabEntries(for tab: SubtitleModuleTab, limit: Int = 8) -> [ProjectBackupIndexEntry] {
        SubtitleDualDraftStore.recentCreateTabEntries(for: tab, limit: limit)
    }

    func loadDraftPreview(_ url: URL) {
        preview.load(url: url)
    }

    func syncPreviewForSubtitleTab(_ tab: SubtitleModuleTab) {
        if let url = SubtitleDualDraftStore.draftURL(
            for: tab,
            whisper: whisperDraftMediaURL,
            script: scriptDraftMediaURL
        ) {
            loadDraftPreview(url)
        } else {
            preview.clear()
        }
    }

    func ensureEditSessionIfNeeded() {
        guard !isEditReady else { return }
        guard let entry = editableProjectEntries(limit: 1).first else { return }
        openRecentProject(at: entry.mediaPath)
    }

    func setMediaURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: SubtitleDualDraftStore.lastMediaPathKey)
        mediaURL = url
        sessionRestored = false
        exportMessage = ""
        burnMessage = ""

        ProjectBackupStore.reconcileCoLocatedFiles(for: url)

        if restoreProjectSession(for: url) {
            sessionRestored = true
            runner.appendLog("✓ Đã khôi phục backup dự án — \(backupPrefs.backupRootURL.lastPathComponent)")
            attachPreviewVideo()
            syncPreferencesContext()
            return
        }

        whisperComplete = false
        translateComplete = false
        activeTranscriptVariant = .original
        segments = []
        transcriptSummary = ""
        srtURL = nil
        resetEditHistory()
        attachPreviewVideo()

        // Video + SRT cùng thư mục (cùng tên) → mở sửa luôn, không cần Whisper.
        let coLocated = ProjectBackupStore.coLocatedSRT(for: url)
        if FileManager.default.fileExists(atPath: coLocated.path) {
            if whisperDraftMediaURL == nil {
                setWhisperDraftMedia(url)
            }
            openExistingSRT(coLocated, mediaAlreadySet: true)
            return
        }

        syncPreferencesContext()
    }

    func setSRTURL(_ url: URL) {
        openExistingSRT(url, mediaAlreadySet: mediaURL != nil)
    }

    /// Mở chỉ file SRT để sửa và xuất lại. Không giữ video/draft cũ, nên không thể chép lời hoặc burn/XML nhầm.
    func openStandaloneSRT(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logActivity("✗ Không tìm thấy SRT")
            return
        }
        mediaURL = nil
        whisperDraftMediaURL = nil
        SubtitleDualDraftStore.clearWhisperDraftPath()
        preview.clear()
        sessionRestored = false
        exportMessage = ""
        burnMessage = ""
        completionSummary = ""
        transcriptSummary = ""
        resetEditHistory()
        openExistingSRT(url, mediaAlreadySet: false)
        logActivity("✓ Mở SRT để chỉnh — (url.lastPathComponent)")
    }

    /// Mở cặp video + SRT có sẵn để sửa (không chạy Whisper).
    func openMediaAndExistingSRT(media: URL, srt: URL) {
        guard FileManager.default.fileExists(atPath: media.path) else {
            logActivity("✗ Không tìm thấy video")
            return
        }
        guard FileManager.default.fileExists(atPath: srt.path) else {
            logActivity("✗ Không tìm thấy SRT")
            return
        }
        UserDefaults.standard.set(media.path, forKey: SubtitleDualDraftStore.lastMediaPathKey)
        mediaURL = media
        setWhisperDraftMedia(media)
        sessionRestored = false
        exportMessage = ""
        burnMessage = ""
        translateComplete = false
        activeTranscriptVariant = .original
        transcriptSummary = ""
        resetEditHistory()
        ProjectBackupStore.reconcileCoLocatedFiles(for: media)
        attachPreviewVideo()
        openExistingSRT(srt, mediaAlreadySet: true)
        logActivity("✓ Mở video + SRT — \(media.lastPathComponent)")
    }

    /// Nạp SRT mang vào (hoặc co-located) và đánh dấu sẵn sàng sửa.
    func openExistingSRT(_ url: URL, mediaAlreadySet: Bool) {
        srtURL = url
        translateComplete = false
        activeTranscriptVariant = .original
        burnMessage = ""
        if let mediaURL {
            ProjectBackupStore.clearTranslatedTranscript(for: mediaURL)
        }
        Task {
            await loadTranscript(from: url, variant: .original)
            // SRT riêng vẫn cần preview để rà cue. Timeline độc lập chỉ dùng
            // timecode SRT, tuyệt đối không dùng lại media của project trước.
            if !mediaAlreadySet, mediaURL == nil {
                preview.loadTimeline(duration: segments.last?.endSeconds ?? 0.01)
            }
            // Coi như đã có bản gốc — bật editor / overlay / xuất như sau Whisper.
            whisperComplete = true
            // SRT nhập vào là dữ liệu biên tập của người dùng: giữ nguyên cue,
            // timing và manual newline. Chỉ STT/provider mới được auto-layout;
            // người dùng có thể chủ động áp bố cục lại từ inspector khi cần.
            if completionSummary.isEmpty, !segments.isEmpty {
                completionSummary = "\(segments.count) đoạn · SRT có sẵn"
            }
            if mediaAlreadySet || mediaURL != nil {
                persistProjectSession()
            }
            logActivity("✓ Đã nạp SRT — \(url.lastPathComponent) · \(segments.count) đoạn")
        }
        syncPreferencesContext()
    }

    func selectTranscriptVariant(_ variant: TranscriptVariant) {
        guard variant != activeTranscriptVariant else { return }
        Task {
            await switchTranscriptVariant(to: variant)
        }
    }

    func syncPreferencesContext() {
        preferences.updateContext(
            mediaURL: mediaURL,
            srtURL: srtURL,
            sourceLang: sourceLang,
            targetLang: targetLang
        )
    }

    func attachPreviewVideo() {
        guard let mediaURL else { return }
        preview.load(url: mediaURL)
    }
    func persistProjectSession() {
        guard let mediaURL else { return }
        ProjectBackupStore.save(
            media: mediaURL,
            srtURL: srtURL,
            targetLang: targetLang,
            sourceLang: sourceLang,
            whisperComplete: whisperComplete,
            translateComplete: translateComplete,
            completionSummary: completionSummary,
            transcriptSummary: transcriptSummary,
            burnStyle: burnStyle
        )
    }

    func clearProjectSession() {
        guard let mediaURL else { return }
        ProjectBackupStore.deleteBackup(for: mediaURL)
        sessionRestored = false
    }
    func loadTranscript(
        from url: URL,
        variant: TranscriptVariant? = nil,
        resetHistory: Bool = true
    ) async {
        let parsed = await Task.detached(priority: .userInitiated) {
            SubtitleCreateJobFinisher.parseSRTFile(url)
        }.value
        segments = parsed
        srtURL = url
        if let variant {
            activeTranscriptVariant = variant
        } else if let mediaURL, ProjectBackupStore.isVaultOriginalSRT(url, media: mediaURL) {
            activeTranscriptVariant = .original
        } else if let mediaURL,
                  let translated = ProjectBackupStore.resolvedTranslatedSRTURL(for: mediaURL, targetLang: targetLang),
                  url.standardizedFileURL == translated.standardizedFileURL {
            activeTranscriptVariant = .translated
        }
        if resetHistory { resetEditHistory() }
    }

    func switchTranscriptVariant(to variant: TranscriptVariant) async {
        guard let mediaURL else { return }
        await flushActiveSegmentsToDisk()

        let targetURL: URL?
        switch variant {
        case .original:
            targetURL = ProjectBackupStore.workingSRTURL(for: mediaURL)
        case .translated:
            targetURL = ProjectBackupStore.resolvedTranslatedSRTURL(for: mediaURL, targetLang: targetLang)
        }

        guard let targetURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            runner.appendLog("⚠️ Không tìm thấy file \(variant.label.lowercased()).")
            return
        }

        await loadTranscript(from: targetURL, variant: variant)
        logActivity(transcriptViewingLabel)
        persistProjectSession()
        syncPreferencesContext()
    }

    func flushActiveSegmentsToDisk() async {
        guard let url = srtURL, !segments.isEmpty else { return }
        let snapshot = segments
        let content = SRTDocument.renderSRT(snapshot)
        do {
            try await Task.detached(priority: .utility) {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }.value
        } catch {
            logActivity("✗ \(error.localizedDescription)")
        }
    }
    func recentProjectEntries(limit: Int = 8) -> [ProjectBackupIndexEntry] {
        ProjectBackupStore.listIndexEntries()
            .filter { FileManager.default.fileExists(atPath: $0.mediaPath) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    func editableProjectEntries(limit: Int = 12) -> [ProjectBackupIndexEntry] {
        recentProjectEntries(limit: 32)
            .filter { Self.isProjectEditable(at: $0.mediaPath) }
            .prefix(limit)
            .map { $0 }
    }

    func projectSubtitleSummary(for entry: ProjectBackupIndexEntry) -> String? {
        let url = URL(fileURLWithPath: entry.mediaPath)
        guard let saved = ProjectBackupStore.load(for: url) else { return nil }
        var parts: [String] = []
        if saved.progress.whisperComplete {
            parts.append("SRT")
        }
        if saved.progress.translateComplete {
            parts.append("đã dịch")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func isProjectEditable(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let url = URL(fileURLWithPath: path)
        if let vault = ProjectBackupStore.resolvedSRTURL(for: url),
           FileManager.default.fileExists(atPath: vault.path) {
            return true
        }
        let coLocated = ProjectBackupStore.coLocatedSRT(for: url)
        return FileManager.default.fileExists(atPath: coLocated.path)
    }

    func openWhisperDraft(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            logActivity("Không tìm thấy file media")
            return
        }
        setWhisperDraftMedia(URL(fileURLWithPath: path))
        syncPreviewForSubtitleTab(.create)
    }

    func openScriptDraft(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            logActivity("Không tìm thấy file media")
            return
        }
        setScriptDraftMedia(URL(fileURLWithPath: path))
        syncPreviewForSubtitleTab(.script)
    }

    func openRecentProject(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            logActivity("Không tìm thấy file media")
            return
        }
        setMediaURL(URL(fileURLWithPath: path))
    }

    func deleteRecentProject(at path: String) {
        let url = URL(fileURLWithPath: path)
        let previewShowsDeleted = preview.currentURL?.path == path
        ProjectBackupStore.deleteBackup(for: url)

        if whisperDraftMediaURL?.path == path {
            whisperDraftMediaURL = nil
            SubtitleDualDraftStore.clearWhisperDraftPath()
        }
        if scriptDraftMediaURL?.path == path {
            scriptDraftMediaURL = nil
            SubtitleDualDraftStore.clearScriptDraftPath()
        }
        SubtitleDualDraftStore.removeFromBothRecentLists(path: path)

        if mediaURL?.path == path {
            UserDefaults.standard.removeObject(forKey: SubtitleDualDraftStore.lastMediaPathKey)
            mediaURL = nil
            srtURL = nil
            segments = []
            transcriptSummary = ""
            whisperComplete = false
            translateComplete = false
            activeTranscriptVariant = .original
            sessionRestored = false
            exportMessage = ""
            burnMessage = ""
            completionSummary = ""
            resetEditHistory()
            whisperCreate.clearLiveState()
            scriptCreate.clearLiveState()
        }

        if previewShowsDeleted {
            preview.clear()
        }

        logActivity("Đã xóa backup dự án")
    }

    func schedulePersistProjectSession() {
        persistSessionTask?.cancel()
        persistSessionTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            persistProjectSession()
        }
    }

    func restoreProjectSession(for media: URL) -> Bool {
        guard let saved = ProjectBackupStore.load(for: media) else { return false }

        targetLang = saved.prefs.targetLang
        sourceLang = saved.prefs.sourceLang
        whisperComplete = saved.progress.whisperComplete
        translateComplete = saved.progress.translateComplete
        completionSummary = saved.completionSummary
        transcriptSummary = ProjectBackupStore.loadSummary(for: media)
        burnStyle = saved.burnStyle

        if saved.progress.translateComplete,
           let translated = ProjectBackupStore.resolvedTranslatedSRTURL(for: media, targetLang: saved.prefs.targetLang),
           FileManager.default.fileExists(atPath: translated.path) {
            srtURL = translated
            translateComplete = true
            Task {
                await loadTranscript(from: translated, variant: .translated)
            }
        } else if let url = ProjectBackupStore.resolvedSRTURL(for: media) {
            srtURL = url
            activeTranscriptVariant = .original
            Task {
                await loadTranscript(from: url, variant: .original)
            }
        }

        return whisperComplete || translateComplete || srtURL != nil
    }
}
