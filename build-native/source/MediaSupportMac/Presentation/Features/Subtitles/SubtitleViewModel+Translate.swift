import Foundation

// MARK: - Dịch / detect / tóm tắt

extension SubtitleViewModel {
    func resolveTranslateInputURL() -> URL? {
        if let mediaURL {
            let working = ProjectBackupStore.workingSRTURL(for: mediaURL)
            if FileManager.default.fileExists(atPath: working.path) {
                return working
            }
        }
        return srtURL
    }

    func resolveTranslateOutputURL(input: URL) -> URL {
        if let mediaURL {
            return ProjectBackupStore.translatedSRTURL(for: mediaURL, targetLang: targetLang)
        }
        return engine.translatedOutputURL(for: input, targetLang: targetLang)
    }

    func generateSummary() async {
        guard !segments.isEmpty, preferences.canSummarize else {
            if let reason = preferences.summaryActionHint {
                runner.appendLog("⚠️ \(reason)")
            }
            return
        }
        isSummarizing = true
        defer { isSummarizing = false }
        let transcript = segments.map(\.text).joined(separator: "\n")
        let detected = mediaURL.flatMap { ProjectBackupStore.languageRecord(for: $0)?.language }
        let outputLang = preferences.resolvedSummaryLanguage(detectedSource: detected)
        runner.appendLog("▶ Tóm tắt bằng \(preferences.translationMode.label)")
        do {
            transcriptSummary = try await TranscriptSummaryService.summarize(
                transcript: transcript,
                sourceLanguageHint: detected,
                outputLanguage: outputLang,
                provider: preferences.translationMode
            )
            runner.appendLog("✓ Tóm tắt xong")
            persistProjectSession()
        } catch {
            runner.appendLog("✗ Tóm tắt: \(error.localizedDescription)")
            cloudAlert = CloudAIErrorClassifier.alert(for: error)
        }
    }
    func detectLanguageFromMedia() {
        guard let mediaURL else { return }
        Task {
            await engine.runDetectMediaLanguage(for: mediaURL)
            syncPreferencesContext()
            await AppleLanguagePackManager.shared.refresh(targetLang: targetLang)
            persistProjectSession()
        }
    }

    func selectTargetLanguage(_ code: String) {
        targetLang = AppleSRTTranslator.normalizeLangCode(code)
        SubtitleLanguageCatalog.recordRecent(targetLang)
        syncPreferencesContext()
    }

    func translateToLanguage(_ code: String) {
        selectTargetLanguage(code)
        runTranslate()
    }

    func runTranslate() {
        Task {
            guard let input = resolveTranslateInputURL() else { return }

            await flushActiveSegmentsToDisk()
            if let mediaURL, !FileManager.default.fileExists(atPath: input.path), !segments.isEmpty {
                _ = ProjectBackupStore.ensureProjectDir(for: mediaURL)
                try? SRTDocument.renderSRT(segments).write(to: input, atomically: true, encoding: .utf8)
            }

            let output = resolveTranslateOutputURL(input: input)
            if let mediaURL {
                try? FileManager.default.createDirectory(
                    at: ProjectBackupStore.exportsDir(for: mediaURL),
                    withIntermediateDirectories: true
                )
            }

            translateComplete = false
            burnMessage = ""
            beginTranslateProgressTracking(estimatedTotal: segments.count)
            defer { endTranslateProgressTracking(succeeded: translateComplete) }
            await engine.runTranslateSRT(
                input: input,
                output: output,
                targetLang: targetLang,
                sourceLang: sourceLang,
                mode: preferences.translationMode,
                mediaURL: mediaURL
            )
            presentLastCloudAlertIfNeeded()
            if runner.lastExitCode == 0, FileManager.default.fileExists(atPath: output.path) {
                if preferences.translationMode == .gemini {
                    preferences.clearGeminiQuotaExceeded()
                }
                if let mediaURL {
                    try? ProjectBackupStore.ingestTranslatedTranscript(
                        from: output,
                        media: mediaURL,
                        targetLang: targetLang
                    )
                }
                await loadTranscript(from: output, variant: .translated)
                translateComplete = true
                attachPreviewVideo()
                runner.appendLog("✓ Dịch xong — \(segments.count) cue → \(targetLang)")
                persistProjectSession()
            } else if preferences.translationMode == .gemini {
                scanTranslateLogsForQuotaIssue()
            }
            syncPreferencesContext()
        }
    }
    func beginTranslateProgressTracking(estimatedTotal: Int) {
        translateProgressCurrent = 0
        translateProgressTotal = max(0, estimatedTotal)
        translateProgressStage = "đang chuẩn bị"
        runner.onLogLine = { [weak self] line in
            self?.handleTranslateLogLine(line)
        }
    }

    func endTranslateProgressTracking(succeeded: Bool) {
        runner.onLogLine = nil
        translateProgressStage = ""
        if succeeded, translateProgressTotal > 0 {
            translateProgressCurrent = translateProgressTotal
        }
    }

    func handleTranslateLogLine(_ line: String) {
        if preferences.translationMode == .gemini, GeminiQuotaSignals.matches(line) {
            preferences.markGeminiQuotaExceeded()
            return
        }
        if line.hasPrefix("⏳ Groq giới hạn tốc độ") {
            translateProgressStage = "chờ Groq"
        } else if line.hasPrefix("… Đang gửi phần") {
            translateProgressStage = "đang gửi"
        } else if line.hasPrefix("↻ Bổ sung") {
            translateProgressStage = "bổ sung"
        }
        guard let progress = Self.parseTranslateBlockProgress(from: line) else { return }
        translateProgressTotal = progress.total
        translateProgressCurrent = progress.current
    }

    func scanTranslateLogsForQuotaIssue() {
        guard preferences.translationMode == .gemini else { return }
        if runner.logLines.contains(where: GeminiQuotaSignals.matches) {
            preferences.markGeminiQuotaExceeded()
        }
    }

    static func parseTranslateBlockProgress(from line: String) -> (current: Int, total: Int)? {
        let pattern = #"(\d+)/(\d+)\s+block"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let currentRange = Range(match.range(at: 1), in: line),
              let totalRange = Range(match.range(at: 2), in: line),
              let current = Int(line[currentRange]),
              let total = Int(line[totalRange]),
              total > 0
        else { return nil }
        return (current, total)
    }
}
