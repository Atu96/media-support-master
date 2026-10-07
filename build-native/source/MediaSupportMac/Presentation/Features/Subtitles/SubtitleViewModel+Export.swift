import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Export / burn / FCPXML / clipboard

extension SubtitleViewModel {
    func notifyExportDelivered(_ kind: ExportDeliverableKind, fileURL: URL? = nil) {
        exportDeliverySignal = ExportDeliverySignal(kind: kind, fileURL: fileURL)
    }

    func notifyExportFailed(_ kind: ExportDeliverableKind) {
        exportDeliverySignal = nil
    }

    /// Media dùng khi xuất — ưu tiên dự án active, rồi draft/preview đang mở.
    func resolvedExportMediaURL() -> URL? {
        if let mediaURL { return mediaURL }
        // Đang sửa SRT độc lập: không mượn draft của tab khác để xuất nhầm vào project video.
        if whisperDraftMediaURL == nil, srtURL != nil { return nil }
        if let whisperDraftMediaURL { return whisperDraftMediaURL }
        if let scriptDraftMediaURL { return scriptDraftMediaURL }
        return preview.currentURL
    }

    var exportBundleURL: URL? {
        guard let mediaURL else { return nil }
        return ProjectBackupStore.resolvedExportBundleDir(for: mediaURL)
    }

    func revealExportBundleInFinder() {
        let lang = activeTranscriptVariant == .translated ? targetLang : nil
        if let media = resolvedExportMediaURL() {
            SRTExportService.revealExportBundle(for: media, targetLang: lang)
            return
        }
        if let srtURL {
            SRTExportService.revealInFinder(srtURL)
        }
    }

    func revealExportDeliverableInFinder(_ fileURL: URL) {
        SRTExportService.revealInFinder(fileURL)
    }

    func copyTranscript() {
        guard !segments.isEmpty else { return }
        SRTExportService.copyToClipboard(SRTDocument.renderTXT(segments))
        logActivity("Đã sao chép TXT")
    }

    func copySummary() {
        guard !transcriptSummary.isEmpty else { return }
        SRTExportService.copyToClipboard(transcriptSummary)
    }

    func exportTXT() {
        guard !segments.isEmpty else {
            logActivity("✗ Chưa có phụ đề để xuất TXT")
            return
        }
        guard let exportMedia = resolvedExportMediaURL() else {
            exportStandaloneTXT()
            return
        }
        logActivity("Đang gom thư mục dự án…")
        let text = SRTDocument.renderTXT(segments)
        let variant = activeTranscriptVariant
        Task {
            do {
                await flushActiveSegmentsToDisk()
                let lang = targetLang
                let export = try await exportBundleAsync(media: exportMedia) { media in
                    switch variant {
                    case .original:
                        try ProjectBackupStore.publishTextDeliverable(text, media: media, extension: "txt")
                    case .translated:
                        try ProjectBackupStore.publishTextDeliverable(
                            text,
                            media: media,
                            targetLang: lang,
                            extension: "txt"
                        )
                    }
                }
                adoptRelocatedMediaIfNeeded(from: exportMedia, to: export.media)
                let label = variant == .original ? "TXT gốc" : "TXT dịch (\(lang))"
                logActivity("✓ \(label) → \(export.deliverable.path)")
                notifyExportDelivered(.txt, fileURL: export.deliverable)
                persistProjectSession()
            } catch {
                notifyExportFailed(.txt)
                logActivity("✗ \(error.localizedDescription)")
            }
        }
    }

    /// TXT là văn bản đọc sạch, không bắt buộc phải có video/project bundle.
    private func exportStandaloneTXT() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let base = srtURL?.deletingPathExtension().lastPathComponent ?? "subtitle"
        panel.nameFieldStringValue = base + ".txt"
        panel.message = "Lưu bản văn bản sạch, không timecode/cue"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let content = SRTDocument.renderTXT(segments)
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try content.write(to: destination, atomically: true, encoding: .utf8)
                }.value
                logActivity("✓ TXT → \(destination.path)")
                notifyExportDelivered(.txt, fileURL: destination)
            } catch {
                notifyExportFailed(.txt)
                logActivity("✗ Xuất TXT thất bại: \(error.localizedDescription)")
            }
        }
    }

    func exportSRT() {
        exportSRTToMediaFolder()
    }

    /// Xuất deliverable bundle — theo variant đang xem: gốc `{tên}.srt` hoặc dịch `{tên}_{lang}.srt`.
    func exportSRTToMediaFolder() {
        guard !segments.isEmpty else {
            logActivity("✗ Chưa có phụ đề để xuất SRT")
            return
        }
        guard let exportMedia = resolvedExportMediaURL() else {
            exportStandaloneSRT()
            return
        }
        logActivity("Đang gom thư mục dự án…")
        let variant = activeTranscriptVariant
        let srtContent = SRTDocument.renderSRT(segments)
        Task {
            do {
                await flushActiveSegmentsToDisk()
                try? persistSegmentsToVault(for: exportMedia)
                let lang = targetLang
                let exportLang = variant == .translated ? lang : nil
                let export = try await exportBundleAsync(media: exportMedia) { media in
                    try ProjectBackupStore.publishTextDeliverable(
                        srtContent,
                        media: media,
                        targetLang: exportLang,
                        extension: "srt"
                    )
                }
                adoptRelocatedMediaIfNeeded(from: exportMedia, to: export.media)
                let dest = export.deliverable
                let label = variant == .original ? "SRT gốc" : "SRT dịch (\(lang))"
                exportMessage = dest.path
                logActivity("✓ \(label) → \(dest.path)")
                notifyExportDelivered(.srt, fileURL: dest)
                persistProjectSession()
            } catch {
                exportMessage = ""
                notifyExportFailed(.srt)
                logActivity("✗ Xuất SRT thất bại: \(error.localizedDescription)")
            }
        }
    }

    /// SRT không có video thì người dùng chọn nơi lưu, thay vì bắt buộc tạo project bundle.
    private func exportStandaloneSRT() {
        guard let source = srtURL else {
            logActivity("✗ Chưa chọn SRT")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [FilePickerHelper.srtType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "_edited.srt"
        panel.message = "Lưu bản SRT đã chỉnh"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let content = SRTDocument.renderSRT(segments)
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try content.write(to: destination, atomically: true, encoding: .utf8)
                }.value
                exportMessage = destination.path
                logActivity("✓ SRT đã chỉnh → \(destination.path)")
                notifyExportDelivered(.srt, fileURL: destination)
            } catch {
                exportMessage = ""
                notifyExportFailed(.srt)
                logActivity("✗ Xuất SRT thất bại: \(error.localizedDescription)")
            }
        }
    }
    func burnSubtitlesIntoVideo() {
        guard let mediaURL, !segments.isEmpty else { return }
        applyProjectBurnStyleForExport()
        burnStyle.save()
        let output = ProjectBackupStore.burnOutputURL(for: mediaURL)
        let styleSnapshot = burnStyle
        let segmentSnapshot = segments
        Task {
            burnMessage = ""
            do {
                if styleSnapshot.hasAppExclusiveEffects {
                    let transition = L10n.string(styleSnapshot.textTransition.localizationKey)
                    let visual = L10n.string(styleSnapshot.visualEffect.localizationKey)
                    logActivity("Đang dựng hiệu ứng nhạc \(transition) · \(visual)…")
                } else {
                    logActivity("Đang gắn phụ đề bằng bộ dựng native…")
                }
                try await SubtitleVideoExporter.export(
                    videoURL: mediaURL,
                    outputURL: output,
                    segments: segmentSnapshot,
                    style: styleSnapshot
                )
            } catch {
                notifyExportFailed(.video)
                logActivity("✗ Xuất video phụ đề thất bại: \(error.localizedDescription)")
                persistProjectSession()
                return
            }
            let exportSucceeded = FileManager.default.fileExists(atPath: output.path)
            if exportSucceeded {
                let message = "Đã gắn: \(output.lastPathComponent)"
                burnMessage = message
                logActivity(message)
                notifyExportDelivered(.video, fileURL: output)
                if backupPrefs.autoPurgeBackupOnBurn {
                    clearProjectSession()
                } else {
                    persistProjectSession()
                }
            } else {
                notifyExportFailed(.video)
                persistProjectSession()
            }
        }
    }

    /// Font/màu/FPS đã lưu trong vault — dùng trước burn (panel Kiểu sub có thể chưa sync).
    func applyProjectBurnStyleForExport() {
        guard let mediaURL,
              let saved = ProjectBackupStore.load(for: mediaURL) else { return }
        burnStyle = saved.burnStyle
    }

    func exportFCPXML() {
        guard let exportMedia = resolvedExportMediaURL(), !segments.isEmpty else {
            logActivity("✗ Chưa chọn video để xuất XML")
            return
        }
        // Panel hiện tại = nguồn sự thật (không load vault ghi đè font/lề).
        burnStyle.save()
        persistProjectSession()
        let styleSnapshot = burnStyle
        logActivity(styleSnapshot.fcpxmlStyleLogLine)
        logActivity(
            "XML CLI: " + styleSnapshot.fcpxmlCLIArgs.joined(separator: " ")
        )
        logActivity("Đang gom thư mục dự án…")
        let variant = activeTranscriptVariant
        Task {
            burnMessage = ""
            do {
                await flushActiveSegmentsToDisk()
                try? persistSegmentsToVault(for: exportMedia)
                guard srtURL != nil || !segments.isEmpty else {
                    logActivity("Chưa có SRT")
                    return
                }
                let lang = targetLang
                // Render từ segments đang xem (text + timing đã chỉnh) — không đọc SRT cũ lệch.
                let srtContent = SRTDocument.renderSRT(segments)
                let exportLang = variant == .translated ? lang : nil
                let export = try await exportBundleAsync(media: exportMedia) { media in
                    try ProjectBackupStore.publishTextDeliverable(
                        srtContent,
                        media: media,
                        targetLang: exportLang,
                        extension: "srt"
                    )
                }
                adoptRelocatedMediaIfNeeded(from: exportMedia, to: export.media)
                let relocatedMedia = export.media
                let exportSRT = export.deliverable
                let output = ProjectBackupStore.bundleDeliverableURL(for: relocatedMedia, extension: "fcpxml")
                await engine.runExportSRTFCPXML(
                    srt: exportSRT,
                    output: output,
                    style: styleSnapshot
                )
                if runner.lastExitCode == 0, FileManager.default.fileExists(atPath: output.path) {
                    try ProjectBackupStore.publishFileDeliverable(
                        from: output,
                        media: relocatedMedia,
                        extension: "fcpxml"
                    )
                    let xmlDest = ProjectBackupStore.packageDeliverableURL(
                        for: relocatedMedia,
                        targetLang: variant == .translated ? lang : nil,
                        extension: "fcpxml"
                    )
                    let message = "✓ XML → \(xmlDest.path)"
                    burnMessage = message
                    logActivity(message)
                    notifyExportDelivered(.xml, fileURL: xmlDest)
                } else {
                    notifyExportFailed(.xml)
                    logActivity("Xuất XML thất bại")
                }
                persistProjectSession()
            } catch {
                notifyExportFailed(.xml)
                logActivity("✗ \(error.localizedDescription)")
            }
        }
    }

    struct ExportBundleResult {
        let bundle: URL
        let media: URL
        let deliverable: URL
    }

    func exportBundleAsync(
        media: URL,
        prepare: @escaping (URL) throws -> URL
    ) async throws -> ExportBundleResult {
        try await Task.detached(priority: .userInitiated) {
            let relocated = try ProjectBackupStore.ensureMediaInExportPackage(media: media)
            let deliverable = try prepare(relocated)
            return ExportBundleResult(
                bundle: ProjectBackupStore.exportBundleDir(for: relocated),
                media: relocated,
                deliverable: deliverable
            )
        }.value
    }

    func persistSegmentsToVault(for media: URL? = nil) throws {
        guard let targetMedia = media ?? mediaURL, !segments.isEmpty else { return }
        ProjectBackupStore.ensureProjectDir(for: targetMedia)
        let dest: URL
        switch activeTranscriptVariant {
        case .original:
            dest = ProjectBackupStore.workingSRTURL(for: targetMedia)
        case .translated:
            dest = ProjectBackupStore.resolvedTranslatedSRTURL(for: targetMedia, targetLang: targetLang)
                ?? ProjectBackupStore.translatedSRTURL(for: targetMedia, targetLang: targetLang)
        }
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try SRTDocument.renderSRT(segments).write(to: dest, atomically: true, encoding: .utf8)
        srtURL = dest
    }
}
