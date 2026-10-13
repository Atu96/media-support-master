import Foundation
import UniformTypeIdentifiers

@MainActor
protocol SubtitleComparisonSession: AnyObject {
    var mediaURL: URL? { get }
    var segments: [SRTSegment] { get }
    var activeTranscriptVariant: TranscriptVariant { get }
    var srtURL: URL? { get }
    var liveEditDraft: (id: Int, text: String)? { get set }
    var sourceLang: String { get set }
    var wrapStyle: SubtitleWrapStyle { get }
    var burnStyle: SubtitleBurnStyle { get }
    var whisperComplete: Bool { get }
    var isApplyingTranscriptLayout: Bool { get }
    var isComparingSubtitles: Bool { get set }
    var isWhisperJobInFlight: Bool { get }
    var isScriptAlignJobInFlight: Bool { get }
    var scriptDraftMediaURL: URL? { get }
    var scriptText: String { get }
    var effectiveScriptAlignmentLanguage: ScriptAlignmentLanguage { get }
    var subtitleComparisonPresented: Bool { get set }
    var subtitleEvidenceCompletion: UUID? { get set }
    var completionSummary: String { get set }
    var engine: MediaEngineServing { get }
    var runner: EngineRunner { get }
    var preview: AVPreviewService { get }
    func cancelComparisonOCR()
    func resolvedSubtitleLanguageCode() -> String
    func applyEditSegments(_ segments: [SRTSegment], recordUndo: Bool)
}

@MainActor
final class SubtitleComparisonController: ObservableObject {
    enum Phase { case offer, ocr, audio, running, review, message }
    struct Snapshot: Sendable {
        let media: URL
        let cues: [SRTSegment]
        let variant: TranscriptVariant
        let srt: URL?
        let draftID: Int?
        let draftText: String?
        let language: String
        let wrap: SubtitleWrapStyle
        let style: SubtitleBurnStyle
    }
    @Published var phase: Phase = .offer
    @Published var candidateIDs: Set<Int> = []
    @Published private(set) var groups: [SubtitleEvidenceGroup] = []
    @Published private(set) var source: SubtitleEvidenceSource = .ocr
    @Published private(set) var message = ""
    @Published private(set) var percent = 0
    @Published private(set) var isRunning = false { didSet { session.isComparingSubtitles = isRunning } }
    @Published private(set) var candidateLanguage = "auto"
    @Published private(set) var failedScriptMatch = false
    @Published var suppressOffers = false {
        didSet { defaults.set(suppressOffers, forKey: "msm.subtitleComparison.suppressOffers") }
    }
    private let defaults: UserDefaults
    private unowned let session: SubtitleComparisonSession
    private var snapshot: Snapshot?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var committing = false
    private var pendingOffer: SubtitleEvidenceSource?
    private var ownsSpeechJob = false
    var speechScanOverride: (@MainActor (URL, URL, Bool) async throws -> Void)?
    var dubbingOverride: DubbingSessionModel?
    private var dubbing: DubbingSessionModel { dubbingOverride ?? DubbingSessionModel.shared }

    init(session: SubtitleComparisonSession, defaults: UserDefaults = .standard) {
        self.session = session; self.defaults = defaults
        suppressOffers = defaults.bool(forKey: "msm.subtitleComparison.suppressOffers")
    }

    var canStart: Bool {
        session.mediaURL != nil && !session.segments.isEmpty && session.liveEditDraft == nil
            && !session.engine.isRunning && !session.isApplyingTranscriptLayout
            && !session.isWhisperJobInFlight && !session.isScriptAlignJobInFlight
            && !dubbing.isRendering && !isRunning
    }
    var hasVideo: Bool {
        guard let media = session.mediaURL, let type = UTType(filenameExtension: media.pathExtension) else { return false }
        return type.conforms(to: .movie)
    }
    var canReuseScript: Bool {
        canStart && session.activeTranscriptVariant == .original && session.whisperComplete
            && session.mediaURL == session.scriptDraftMediaURL
    }

    func noteCompletion(_ source: SubtitleEvidenceSource) {
        // Only primary OCR invites an audio cross-check; audio completion also
        // clears any deferred OCR offer from an earlier result.
        pendingOffer = source == .ocr ? .ocr : nil
        guard pendingOffer != nil else { return }
        session.subtitleEvidenceCompletion = UUID()
    }

    func presentOfferIfEligible() {
        guard !suppressOffers, hasVideo, canStart, !session.subtitleComparisonPresented,
              pendingOffer == .ocr else { return }
        pendingOffer = nil
        open(source: .audio, offer: true)
    }

    func open(source: SubtitleEvidenceSource, offer: Bool = false) {
        guard canStart, source != .ocr || hasVideo, let media = session.mediaURL else { return }
        pendingOffer = nil
        generation = UUID()
        snapshot = Snapshot(media: media, cues: session.segments, variant: session.activeTranscriptVariant,
            srt: session.srtURL, draftID: session.liveEditDraft?.id, draftText: session.liveEditDraft?.text,
            language: session.resolvedSubtitleLanguageCode(), wrap: session.wrapStyle, style: session.burnStyle)
        self.source = source
        groups = []; candidateIDs = []; message = ""; percent = 0; failedScriptMatch = false
        phase = offer ? .offer : (source == .ocr ? .ocr : .audio)
        session.subtitleComparisonPresented = true
    }

    func continueOffer() { phase = source == .ocr ? .ocr : .audio }

    func dismiss() {
        cancel()
        pendingOffer = nil
        session.subtitleComparisonPresented = false
        groups = []; candidateIDs = []; snapshot = nil
    }

    func invalidate() {
        guard !committing else { return }
        pendingOffer = nil
        guard snapshot != nil || isRunning else { return }
        dismiss()
    }

    func cancel() {
        task?.cancel()
        if ownsSpeechJob { session.runner.cancel() }
        if phase == .ocr { session.cancelComparisonOCR() }
    }

    private func matches(_ snap: Snapshot) -> Bool {
        session.mediaURL == snap.media && session.segments == snap.cues
            && session.activeTranscriptVariant == snap.variant && session.srtURL == snap.srt
            && session.liveEditDraft?.id == snap.draftID && session.liveEditDraft?.text == snap.draftText
            && session.wrapStyle == snap.wrap && session.burnStyle == snap.style
            && session.resolvedSubtitleLanguageCode() == snap.language
    }

    func receiveOCR(_ result: SubtitleOCRResult) {
        guard let snap = snapshot, matches(snap), phase == .ocr else { return }
        prepareReview(cues: result.segments, language: result.language)
    }

    func runAudio(offline: Bool) {
        guard let snap = snapshot, matches(snap), canStart else { return }
        session.preview.pause()
        isRunning = true; phase = .running; percent = 0
        message = L10n.string("Đang lấy bản bổ trợ từ âm thanh…")
        let id = generation
        let scan = speechScanOverride
        task = Task { [weak self] in
            guard let self else { return }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("msm-comparison-\(UUID().uuidString).srt")
            defer { try? FileManager.default.removeItem(at: output) }
            session.runner.onLogLine = { [weak self] line in
                guard let self, self.generation == id else { return }
                if let value = WhisperProgressParser.percent(from: line) { self.percent = max(self.percent, min(97, value)) }
                if !line.hasPrefix("MSM_PROGRESS:") { self.message = line }
            }
            defer { session.runner.onLogLine = nil }
            do {
                try Task.checkCancellation()
                if let scan { try await scan(snap.media, output, offline) }
                else {
                    self.ownsSpeechJob = true
                    await session.engine.runComparisonSpeechSRT(for: snap.media, output: output,
                        sourceLang: "auto", offline: offline)
                    self.ownsSpeechJob = false
                    guard session.runner.lastExitCode == 0 else {
                        if session.runner.lastExitCode == 130 { throw CancellationError() }
                        throw SubtitleEvidenceError.invalidTiming
                    }
                }
                try Task.checkCancellation()
                let cues = await Task.detached(priority: .utility) {
                    SubtitleCreateJobFinisher.parseSRTFile(output)
                }.value
                guard self.generation == id, self.matches(snap) else { throw CancellationError() }
                self.isRunning = false
                self.ownsSpeechJob = false
                self.task = nil
                self.prepareReview(cues: cues, language: ScriptLanguageDetector.detect(from: cues.map(\.text).joined(separator: " "))?.rawValue ?? "auto")
                return
            } catch {
                guard self.generation == id else { return }
                self.isRunning = false
                self.phase = .message
                self.message = error is CancellationError
                    ? L10n.string("Đã dừng đối chiếu; phụ đề hiện có được giữ nguyên.")
                    : (session.runner.lastCloudAlert?.message ?? L10n.string("Không lấy được bản bổ trợ. Phụ đề hiện có được giữ nguyên; xem nhật ký để biết lỗi."))
            }
            if self.generation == id { self.task = nil }
        }
    }

    private func prepareReview(cues: [SRTSegment], language: String) {
        guard let snap = snapshot else { return }
        let id = generation
        isRunning = true; phase = .running
        message = L10n.string("Đang đối chiếu các cue…")
        task = Task { [weak self] in
            guard let self else { return }
            let worker = Task.detached(priority: .utility) { try SubtitleEvidenceComparison.groups(current: snap.cues, candidate: cues) }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard self.generation == id, self.matches(snap) else { throw CancellationError() }
                self.groups = result; self.candidateLanguage = language
                self.percent = 100; self.message = ""; self.phase = .review
            } catch {
                guard self.generation == id else { return }
                self.phase = .message; self.message = error.localizedDescription
            }
            if self.generation == id { self.isRunning = false; self.task = nil }
        }
    }

    func applyChoices() {
        guard let snap = snapshot, matches(snap), !isRunning, !session.engine.isRunning,
              !dubbing.isRendering, !candidateIDs.isEmpty else { return }
        let choices = candidateIDs, groups = groups
        apply(snap: snap) { try SubtitleEvidenceComparison.planned(groups, candidateIDs: choices) }
    }

    func applyOriginalScript() {
        guard canReuseScript, let media = session.mediaURL else { return }
        let script = session.scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = session.effectiveScriptAlignmentLanguage.rawValue
        let snap = Snapshot(media: media, cues: session.segments, variant: session.activeTranscriptVariant,
            srt: session.srtURL, draftID: nil, draftText: nil, language: session.resolvedSubtitleLanguageCode(),
            wrap: session.wrapStyle, style: session.burnStyle)
        snapshot = snap; generation = UUID()
        failedScriptMatch = false
        apply(snap: snap, script: script, language: language) {
            let replacement = try ExistingCueScriptMapper.replace(script: script, cues: snap.cues, language: language)
            let config = SubtitleLayoutConfiguration(languageCode: language, fontName: snap.style.fontName,
                fontSize: Double(snap.style.fontSize), containerWidth: max(120,
                    Double(VideoPreviewFrame.classify(displaySize: VideoGeometryProbe.displaySize(for: media)).referencePixelSize.width)
                        * Double(snap.style.boxMaxWidthRatio) - 24),
                maxLines: snap.wrap.maxLines,
                requiresTwoLines: snap.wrap.maxLines == 2,
                preferredCharactersPerLine: SubtitleWrapStyle.effectiveMaxCharsPerLine(base: snap.wrap.maxCharsPerLine, fontSize: snap.style.fontSize),
                topLineRatio: snap.wrap.topLineRatio.topOverBottom, explicitBreakPolicy: .automatic)
            return replacement.map { cue in
                let text = SubtitleLayoutEngine.layoutSingleCue(cue.text, configuration: config)?.text ?? cue.text
                return SRTSegment(id: cue.id, index: cue.index, timing: cue.timing,
                    startSeconds: cue.startSeconds, endSeconds: cue.endSeconds, text: text)
            }
        }
    }

    private func apply(snap: Snapshot, script: String? = nil, language: String? = nil,
                       operation: @escaping @Sendable () throws -> [SRTSegment]) {
        let id = generation
        let cache = dubbing.qualityRepairCacheSnapshot()
        isRunning = true
        message = L10n.string("Đang áp dụng lựa chọn…")
        task = Task { [weak self] in
            guard let self else { return }
            let worker = Task.detached(priority: .utility) {
                let planned = try operation()
                if let script, planned.map(\.text).joined().filter({ !$0.isWhitespace }) != script.filter({ !$0.isWhitespace }) {
                    throw SubtitleEvidenceError.scriptMismatch
                }
                try SubtitleEvidenceComparison.validate(planned)
                try cache.preserveClips(previous: snap.cues, planned: planned)
                return planned
            }
            do {
                let planned = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard self.generation == id, self.matches(snap), !self.session.engine.isRunning,
                      !self.dubbing.isRendering,
                      script == nil || self.session.scriptText.trimmingCharacters(in: .whitespacesAndNewlines) == script,
                      language == nil || self.session.effectiveScriptAlignmentLanguage.rawValue == language else {
                    throw CancellationError()
                }
                self.committing = true
                self.dubbing.preserveQualityRepairRates(cache.preservedRates(previous: snap.cues, planned: planned))
                self.session.applyEditSegments(SRTSegmentEditor.reindexed(planned), recordUndo: true)
                if let language { self.session.sourceLang = language }
                self.session.liveEditDraft = nil
                self.session.completionSummary = L10n.string(script == nil ? "Đã áp dụng lựa chọn đối chiếu. Có thể Hoàn tác." : "Đã ưu tiên văn bản gốc, giữ thời gian cue. Có thể Hoàn tác.")
                self.committing = false
                self.session.subtitleComparisonPresented = false
                self.snapshot = nil; self.groups = []
            } catch {
                guard self.generation == id else { return }
                self.phase = .message; self.message = error.localizedDescription
                self.failedScriptMatch = script != nil && !(error is CancellationError)
                if !(error is CancellationError) { self.session.subtitleComparisonPresented = true }
            }
            if self.generation == id {
                self.isRunning = false; self.task = nil
            }
        }
    }
}
