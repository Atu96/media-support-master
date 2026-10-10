import Foundation

@MainActor
final class SubtitleOCRCreateController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var percent = 0
    @Published private(set) var cueCount = 0
    @Published private(set) var message = ""
    @Published private(set) var succeeded = false
    private unowned let session: SubtitleViewModel
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private var activeMedia: URL?
    private var isCommitting = false

    init(session: SubtitleViewModel) { self.session = session }

    func prepare() {
        guard !isRunning else { return }
        percent = 0
        cueCount = 0
        message = ""
        succeeded = false
    }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        session.runner.cancel()
    }

    func cancelIfMediaChanged(to media: URL?) {
        if isRunning, !isCommitting, media != activeMedia { cancel() }
    }

    func cancelIfSessionEdited() {
        if isRunning, !isCommitting { cancel() }
    }

    func run(media: URL, region: SubtitleOCRRegion, interval: Double) {
        guard !isRunning, !session.engine.isRunning else { return }
        session.preview.pause()
        let originalMedia = session.mediaURL
        let originalSegments = session.segments
        let originalVariant = session.activeTranscriptVariant
        let originalSRT = session.srtURL
        let originalDraft = session.liveEditDraft
        let id = UUID()
        generation = id
        activeMedia = media
        isRunning = true
        percent = 0
        cueCount = 0
        succeeded = false
        message = L10n.string("Đang đọc chữ trong vùng đã chọn…")
        task = Task { [weak self] in
            guard let self else { return }
            await session.runner.runTask(title: L10n.string("Lấy phụ đề từ hình ảnh")) { [self] in
                let result = try await SubtitleOCRService.scan(media: media, region: region, interval: interval) { [weak controller = self] progress, count in
                    await controller?.update(progress: progress, count: count, generation: id)
                }
                try Task.checkCancellation()
                guard self.generation == id, self.session.mediaURL == originalMedia,
                      self.session.segments == originalSegments, self.session.activeTranscriptVariant == originalVariant,
                      self.session.srtURL == originalSRT, self.session.liveEditDraft?.id == originalDraft?.id,
                      self.session.liveEditDraft?.text == originalDraft?.text else {
                    throw CancellationError()
                }
                // Commit only a complete scan, directly to the canonical working transcript.
                self.isCommitting = true
                defer { self.isCommitting = false }
                ProjectBackupStore.ensureProjectDir(for: media)
                let output = ProjectBackupStore.workingSRTURL(for: media)
                try SRTDocument.renderSRT(result.segments).write(to: output, atomically: true, encoding: .utf8)
                try ProjectBackupStore.ingestTranscript(from: output, media: media)
                self.session.adoptMediaForOCRTranscript(media)
                self.session.srtURL = output
                self.session.segments = result.segments
                self.session.activeTranscriptVariant = .original
                self.session.whisperComplete = true
                self.session.translateComplete = false
                self.session.transcriptSummary = ""
                self.session.liveEditDraft = nil
                self.session.previewFocusSegmentID = nil
                self.session.sourceLang = result.language
                ProjectBackupStore.clearTranslatedTranscript(for: media)
                self.session.resetEditHistory()
                self.session.attachPreviewVideo()
                self.session.syncPreferencesContext()
                self.session.persistProjectSession()
                self.percent = 100
                self.cueCount = result.segments.count
                self.succeeded = true
                self.message = L10n.format("Đã lấy %d cue · %@", result.segments.count,
                    Locale(identifier: L10n.interfaceLocaleIdentifier).localizedString(forLanguageCode: result.language)
                        ?? self.session.languageDisplayName(result.language))
                self.session.completionSummary = self.message
                self.session.runner.appendLog(self.message)
            }
            guard self.generation == id else { return }
            if !self.succeeded {
                self.message = self.session.runner.lastExitCode == 130
                    ? L10n.string("Đã dừng quét; phụ đề hiện có được giữ nguyên.")
                    : L10n.string("Quét chưa hoàn tất; phụ đề hiện có được giữ nguyên. Xem nhật ký để biết lỗi.")
            }
            self.isRunning = false
            self.task = nil
        }
    }

    private func update(progress: Double, count: Int, generation: UUID) {
        guard self.generation == generation, !Task.isCancelled else { return }
        percent = max(percent, min(97, Int(progress * 100)))
        cueCount = count
    }
}
