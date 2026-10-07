import Foundation

// MARK: - Trạng thái suy ra cho giao diện

extension SubtitleViewModel {
    var runner: EngineRunner {
        engine.runner
    }

    var summaryOutputLabel: String {
        preferences.summaryOutputLabel
    }

    var hasDraftSession: Bool {
        guard let mediaURL else { return false }
        return ProjectBackupStore.hasBackup(for: mediaURL)
    }

    var isRunningWhisper: Bool {
        // Engine process + giai đoạn parse/nạp UI (process đã thoát nhưng % vẫn hiện).
        isWhisperJobInFlight || whisperCreate.isRunning
    }

    var isRunningScriptAlign: Bool {
        isScriptAlignJobInFlight || scriptCreate.isRunning
    }

    var canRunWhisper: Bool {
        whisperDraftMediaURL != nil
            && GroqCredentialStore.hasKey
            && !engine.isRunning
    }

    var canRunScriptAlign: Bool {
        scriptDraftMediaURL != nil
            && !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && canRunEngine
    }

    var canOpenEditTab: Bool {
        isEditReady || hasAnyEditableProject
    }

    var hasAnyEditableProject: Bool {
        !editableProjectEntries(limit: 1).isEmpty
    }

    func isActiveProject(_ url: URL) -> Bool {
        mediaURL?.standardizedFileURL == url.standardizedFileURL
    }

    var whisperTabShowsTranscript: Bool {
        guard let draft = whisperDraftMediaURL, isActiveProject(draft) else { return false }
        return isRunningWhisper || (!segments.isEmpty && whisperComplete)
    }

    var scriptTabShowsTranscript: Bool {
        guard let draft = scriptDraftMediaURL, isActiveProject(draft) else { return false }
        return isRunningScriptAlign || (!segments.isEmpty && whisperComplete)
    }

    var isBurningSubtitles: Bool {
        engine.isRunning && runner.currentJobTitle?.contains("Gắn sub") == true
    }

    var isRunningTranslate: Bool {
        engine.isRunning && runner.currentJobTitle?.contains("Dịch") == true
    }

    var usesVaultOriginalSRT: Bool {
        guard whisperComplete, let mediaURL, let srtURL else { return false }
        return ProjectBackupStore.isVaultOriginalSRT(srtURL, media: mediaURL)
    }

    var translateSourceLangLabel: String {
        if sourceLang == "auto", !detectedSourceLabel.isEmpty {
            return detectedSourceLabel
        }
        return languageDisplayName(sourceLang)
    }

    var translateRouteLabel: String {
        "\(translateSourceLangLabel) → \(languageDisplayName(targetLang))"
    }

    var translateProjectStatusLine: String? {
        guard mediaURL != nil || srtURL != nil else { return nil }
        var parts: [String] = []
        if let mediaURL {
            parts.append(mediaURL.lastPathComponent)
        }
        if !segments.isEmpty {
            parts.append("\(segments.count) cue")
        }
        parts.append(translateRouteLabel)
        parts.append(hasTranslatedTranscript || translateComplete ? "đã dịch" : "chưa dịch")
        return parts.joined(separator: " · ")
    }

    var translateProgressPercent: Int {
        guard translateProgressTotal > 0 else { return 0 }
        return min(
            100,
            Int(round(Double(translateProgressCurrent) / Double(translateProgressTotal) * 100))
        )
    }

    var translateProgressLabel: String {
        guard translateProgressTotal > 0 else { return "Đang dịch…" }
        return "\(translateProgressCurrent)/\(translateProgressTotal) block"
    }

    var canBurnSubtitles: Bool {
        mediaURL != nil && srtURL != nil && canRunEngine
    }

    var showSubtitleOverlay: Bool {
        // Có cue là hiện overlay (kể cả SRT mang vào, không qua Whisper).
        !segments.isEmpty
    }

    var isEditReady: Bool {
        srtURL != nil && !segments.isEmpty
    }

    var detectedSourceLabel: String {
        preferences.detectedSourceLabel
    }

    var canRunEngine: Bool {
        coordinatorEngineIsReady && !engine.isRunning
    }

    var canRunTranslate: Bool {
        preferences.canTranslate && !engine.isRunning
    }

    var translateDisabledReason: String? {
        preferences.actionHint
    }

    var canRunSummary: Bool {
        preferences.canSummarize && !isSummarizing
    }

    var summaryDisabledReason: String? {
        preferences.summaryActionHint
    }

    var needsCloudKeySettings: Bool {
        switch preferences.translationMode {
        case .appleLocal:
            return false
        case .gemini:
            return preferences.geminiQuotaExceeded || !GeminiCredentialStore.hasKey
        case .groq:
            return !GroqCredentialStore.hasKey
        }
    }

    var canDetectFromMedia: Bool {
        mediaURL != nil && canRunEngine
    }

    var hasTranslatedTranscript: Bool {
        guard let mediaURL else { return false }
        return ProjectBackupStore.resolvedTranslatedSRTURL(
            for: mediaURL,
            targetLang: targetLang
        ) != nil
    }

    var canSwitchTranscriptVariant: Bool {
        hasTranslatedTranscript
    }

    var activeTranscriptVariantLabel: String {
        switch activeTranscriptVariant {
        case .original: "Gốc"
        case .translated: "Đã dịch (\(targetLang))"
        }
    }

    var transcriptViewingLabel: String {
        switch activeTranscriptVariant {
        case .original: "Đang xem: bản gốc"
        case .translated: "Đang xem: bản dịch (\(targetLang))"
        }
    }

    var transcriptVariantToggleHint: String {
        guard canSwitchTranscriptVariant else { return "" }
        switch activeTranscriptVariant {
        case .original: return "Bấm để xem bản dịch"
        case .translated: return "Bấm để xem bản gốc"
        }
    }

    func toggleTranscriptVariant() {
        guard canSwitchTranscriptVariant else { return }
        let next: TranscriptVariant = activeTranscriptVariant == .original ? .translated : .original
        selectTranscriptVariant(next)
    }

    func logActivity(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("✓")
            || trimmed.hasPrefix("✗")
            || trimmed.hasPrefix("⚠️")
            || trimmed.hasPrefix("ℹ️") {
            runner.appendLog(trimmed)
        } else {
            runner.appendLog("ℹ️ \(trimmed)")
        }
    }

    func languageDisplayName(_ code: String) -> String {
        switch code.lowercased() {
        case "ja": "Japanese"
        case "zh", "zh-cn": "Chinese"
        case "ko": "Korean"
        case "vi": "Vietnamese"
        case "en": "English"
        case "ru": "Russian"
        case "fr": "French"
        case "es": "Spanish"
        case "pt": "Portuguese"
        case "de": "German"
        case "it": "Italian"
        case "th": "Thai"
        default: code.uppercased()
        }
    }
}
