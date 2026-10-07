import Foundation

// MARK: - Transcript edit (cue text / wrap / undo / timing móng)

extension SubtitleViewModel {
    func seekToSegment(_ segment: SRTSegment, playAfter: Bool = true, forEditPreview: Bool = false) {
        previewFocusSegmentID = segment.id
        if !preview.isLoaded, let mediaURL {
            preview.load(url: mediaURL)
        }
        let seconds = forEditPreview ? segment.editPreviewSeekTime() : segment.startSeconds
        if forEditPreview, !playAfter {
            preview.seekForEdit(seconds: seconds)
        } else {
            preview.seek(seconds: seconds, playAfter: playAfter)
        }
    }

    func updateSegmentText(id: Int, text: String) {
        guard let updated = transcriptStore.updatingText(
            in: segments,
            id: id,
            text: text,
            wrapStyle: wrapStyle,
            fontSize: burnStyle.fontSize
        ) else {
            liveEditDraft = nil
            return
        }
        applyEditSegments(updated)
        previewFocusSegmentID = id
        liveEditDraft = nil
    }

    /// Gõ trong editor — preview bám theo từng lần đổi (xuống dòng Enter).
    func setLiveEditDraft(id: Int, text: String) {
        previewFocusSegmentID = id
        liveEditDraft = (id, text.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    func clearLiveEditDraft() {
        liveEditDraft = nil
    }

    /// Áp auto-ngắt cho toàn bộ cue (đổi chữ/dòng, nạp SRT, cỡ chữ…).
    func applyAutoWrapToAllSegments(recordUndo: Bool = true) {
        guard let updated = transcriptStore.rewrappingAll(
            segments,
            wrapStyle: wrapStyle,
            fontSize: burnStyle.fontSize
        ) else { return }
        applyEditSegments(updated, recordUndo: recordUndo)
    }

    /// Đặt lại bố cục sau chép lời theo đúng pipeline STT: khi cue quá dài thì
    /// tách cue và phân lại timing cục bộ; không gọi API hay chạy Whisper lại.
    func applyTranscriptLayoutToAllSegments(recordUndo: Bool = true) {
        guard !segments.isEmpty else { layoutReflow.cancel(); return }
        let snapshot = segments
        let media = mediaURL
        let variant = activeTranscriptVariant
        let language = resolvedSubtitleLanguageCode()
        let wrap = wrapStyle
        let fontSize = burnStyle.fontSize
        let fontName = burnStyle.fontName
        let boxRatio = burnStyle.boxMaxWidthRatio
        layoutReflow.schedule(operation: {
            // Cả probe video lẫn layout chạy ngoài MainActor.
            let displaySize = media.map { VideoGeometryProbe.displaySize(for: $0) }
                ?? CGSize(width: 1920, height: 1080)
            let frame = VideoPreviewFrame.classify(displaySize: displaySize)
            let width = max(Double(fontSize) * 2,
                            Double(frame.referencePixelSize.width) * Double(boxRatio) - 24)
            return SubtitleTranscriptPostProcessor.format(
                snapshot, sourceLanguage: language, style: wrap,
                fontSize: fontSize, fontName: fontName, containerWidth: width,
                // Reflow không còn word timestamps của lượt STT cũ. Giữ các
                // gap cue đang có để không ghép ngược qua khoảng nghỉ rõ rệt.
                maximumSpeechGap: SubtitleLayoutEngine.family(languageCode: language,
                    text: snapshot.first?.text ?? "") == .japanese ? nil : 0.45
            )
        }, completion: { [weak self] updated in
            guard let self,
                  self.mediaURL == media, self.activeTranscriptVariant == variant,
                  self.segments == snapshot, self.wrapStyle == wrap,
                  self.burnStyle.fontSize == fontSize, self.burnStyle.fontName == fontName,
                  self.burnStyle.boxMaxWidthRatio == boxRatio,
                  self.resolvedSubtitleLanguageCode() == language,
                  self.liveEditDraft == nil, updated != snapshot else { return }
            self.applyEditSegments(updated, recordUndo: recordUndo)
        })
    }

    var subtitleLayoutContainerWidth: Double {
        let displaySize = mediaURL.map { VideoGeometryProbe.displaySize(for: $0) }
            ?? CGSize(width: 1920, height: 1080)
        let frame = VideoPreviewFrame.classify(displaySize: displaySize)
        let boxWidth = Double(frame.referencePixelSize.width) * Double(burnStyle.boxMaxWidthRatio)
        // Khớp hai padding ngang 12 px @ canvas tham chiếu trong preview.
        return max(Double(burnStyle.fontSize) * 2, boxWidth - 24)
    }

    func subtitleLayoutConfiguration(
        explicitBreakPolicy: SubtitleExplicitBreakPolicy = .preserve
    ) -> SubtitleLayoutConfiguration {
        SubtitleLayoutConfiguration(
            languageCode: resolvedSubtitleLanguageCode(),
            fontName: burnStyle.fontName,
            fontSize: Double(burnStyle.fontSize),
            containerWidth: subtitleLayoutContainerWidth,
            maxLines: wrapStyle.maxLines,
            preferredCharactersPerLine: SubtitleWrapStyle.effectiveMaxCharsPerLine(
                base: wrapStyle.maxCharsPerLine,
                fontSize: burnStyle.fontSize
            ),
            topLineRatio: wrapStyle.topLineRatio.topOverBottom,
            explicitBreakPolicy: explicitBreakPolicy
        )
    }

    func mergeSegments(ids: Set<Int>) -> Bool {
        let previous = segments
        guard let merged = transcriptStore.merging(
            previous,
            ids: ids,
            wrapStyle: wrapStyle,
            fontSize: burnStyle.fontSize
        ) else { return false }
        applyEditSegments(merged)
        DubbingSessionModel.shared.preserveRenderedAudioAfterMerge(
            previousCues: previous,
            updatedCues: merged,
            mergedSourceIDs: ids
        )
        return true
    }

    func splitSegment(id: Int) -> Bool {
        let lang = resolvedSubtitleLanguageCode()
        guard let split = transcriptStore.splitting(segments, id: id, languageCode: lang) else { return false }
        applyEditSegments(split)
        return true
    }

    func resolvedSubtitleLanguageCode() -> String {
        if activeTranscriptVariant == .translated {
            let translated = targetLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !translated.isEmpty, translated != "auto" { return translated }
        }
        if let mediaURL, let record = ProjectBackupStore.languageRecord(for: mediaURL) {
            return record.language
        }
        let trimmed = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "auto" ? "auto" : trimmed
    }

    func deleteSegment(id: Int) -> Bool {
        guard let deleted = transcriptStore.deleting(segments, id: id) else { return false }
        applyEditSegments(deleted)
        return true
    }

    func deleteSegments(ids: Set<Int>) -> Bool {
        guard let deleted = transcriptStore.deleting(segments, ids: ids) else { return false }
        applyEditSegments(deleted)
        return true
    }

    /// Móng timeline: dời cue theo delta (giây). Chưa gắn UI.
    @discardableResult
    func moveSegment(id: Int, deltaSeconds: Double) -> Bool {
        guard let moved = transcriptStore.moving(segments, id: id, delta: deltaSeconds) else { return false }
        applyEditSegments(moved)
        previewFocusSegmentID = id
        return true
    }

    /// Móng timeline: trim in/out. Chưa gắn UI.
    @discardableResult
    func trimSegment(id: Int, newStart: Double? = nil, newEnd: Double? = nil) -> Bool {
        var current = segments
        var any = false
        if let newStart, let trimmed = transcriptStore.trimmingStart(current, id: id, newStart: newStart) {
            current = trimmed
            any = true
        }
        if let newEnd, let trimmed = transcriptStore.trimmingEnd(current, id: id, newEnd: newEnd) {
            current = trimmed
            any = true
        }
        guard any else { return false }
        applyEditSegments(current)
        previewFocusSegmentID = id
        return true
    }

    func undoEdit() {
        layoutReflow.cancel()
        guard let restored = transcriptStore.undo(current: segments) else { return }
        segments = restored
        syncEditHistoryState()
        schedulePersistEditedSegments()
        logActivity("Hoàn tác")
    }

    func redoEdit() {
        layoutReflow.cancel()
        guard let restored = transcriptStore.redo(current: segments) else { return }
        segments = restored
        syncEditHistoryState()
        schedulePersistEditedSegments()
        logActivity("Làm lại")
    }

    func applyEditSegments(_ updated: [SRTSegment], recordUndo: Bool = true) {
        layoutReflow.cancel()
        segments = transcriptStore.apply(updated, current: segments, recordUndo: recordUndo)
        syncEditHistoryState()
        schedulePersistEditedSegments()
    }

    func syncEditHistoryState() {
        canUndoEdit = transcriptStore.canUndo
        canRedoEdit = transcriptStore.canRedo
    }

    func resetEditHistory() {
        transcriptStore.resetHistory()
        syncEditHistoryState()
    }

    func schedulePersistEditedSegments() {
        persistEditTask?.cancel()
        persistEditTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await persistEditedSegmentsNow()
        }
    }

    func persistEditedSegmentsNow() async {
        guard let srtURL else { return }
        let snapshot = segments
        let url = srtURL
        let content = SRTDocument.renderSRT(snapshot)

        do {
            try await Task.detached(priority: .utility) {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }.value
            logActivity("Đã lưu chỉnh sửa")
            schedulePersistProjectSession()
        } catch {
            logActivity("✗ \(error.localizedDescription)")
        }
    }
}
