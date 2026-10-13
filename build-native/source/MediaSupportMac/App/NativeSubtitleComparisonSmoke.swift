import Foundation

/// TEST-only fake session, private SRT/cache, no credential access or paid services.
@MainActor
enum NativeSubtitleComparisonSmoke {
    private final class Speech: DubbingSpeechSynthesizing {
        var availableVoices: [DubbingVoiceDescriptor] { [] }
        func render(_ request: DubbingSpeechRequest) async throws { throw CancellationError() }
        func stop() {}
    }
    private final class Session: SubtitleComparisonSession, SubtitleCreateSession {
        var mediaURL: URL?
        var segments: [SRTSegment] = []
        var activeTranscriptVariant = TranscriptVariant.original
        var srtURL: URL?
        var liveEditDraft: (id: Int, text: String)?
        var sourceLang = "en"
        var wrapStyle = SubtitleWrapStyle()
        var burnStyle = SubtitleBurnStyle()
        var whisperComplete = true
        var isApplyingTranscriptLayout = false
        var isComparingSubtitles = false
        var isWhisperJobInFlight = false
        var isScriptAlignJobInFlight = false
        var scriptDraftMediaURL: URL?
        var whisperDraftMediaURL: URL?
        var scriptAlignmentLanguage = ScriptAlignmentLanguage.english
        var subtitleLayoutContainerWidth: Double { 1000 }
        var translateComplete = false
        var exportMessage = ""
        var transcriptSummary = ""
        var whisperProgressPercent = 0
        var scriptAlignProgressPercent = 0
        var scriptText = ""
        var effectiveScriptAlignmentLanguage = ScriptAlignmentLanguage.english
        var subtitleComparisonPresented = false
        var subtitleEvidenceCompletion: UUID?
        var completionSummary = ""
        var engine: MediaEngineServing { MediaEngineService.shared }
        var runner: EngineRunner { engine.runner }
        var preview: AVPreviewService { .shared }
        var history = SubtitleEditHistory()
        func isActiveProject(_ url: URL) -> Bool { mediaURL == url }
        func setMediaURL(_ url: URL) { mediaURL = url }
        func attachPreviewVideo() {}
        func resetEditHistory() { history = SubtitleEditHistory() }
        func persistProjectSession() {}
        func syncPreferencesContext() {}
        func refreshEngineStatus() {}
        func languageDisplayName(_ code: String) -> String { code }
        func presentLastCloudAlertIfNeeded() {}
        func presentWhisperCloudAlertIfNeeded() {}
        func didCompleteSubtitleSource(_ source: SubtitleEvidenceSource) {}
        func resolvedSubtitleLanguageCode() -> String { sourceLang }
        func cancelComparisonOCR() {}
        func applyEditSegments(_ updated: [SRTSegment], recordUndo: Bool) {
            if recordUndo { history.record(before: segments) }
            segments = updated
        }
    }
    private static func cue(_ id: Int, _ start: Double, _ end: Double, _ text: String) -> SRTSegment {
        SRTSegment(id: id, index: id, timing: SRTTimecode.makeTiming(start: start, end: end),
            startSeconds: start, endSeconds: end, text: text)
    }
    private static func check(_ value: Bool, _ name: String) throws {
        if !value { throw NSError(domain: "ComparisonSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    }
    private static func drain(_ controller: SubtitleComparisonController) async throws {
        let deadline = Date().addingTimeInterval(10)
        while controller.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try check(!controller.isRunning, "controller did not drain")
    }
    static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Argument-domain overrides are process-local; never move/reset user backups.
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixtureArguments = originalArguments
        fixtureArguments["msm.backupRoot"] = directory.appendingPathComponent("backups").path
        fixtureArguments["msm.backupRetentionDays"] = 0
        fixtureArguments["msm.mirrorSRTBesideMedia"] = false
        fixtureArguments["msm.offlineWhisper.useForNextRun"] = false
        UserDefaults.standard.setVolatileDomain(fixtureArguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain) }
        let suite = "msm.comparison.smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let dubbing = DubbingSessionModel.optimizationSmokeSession(defaults: defaults,
            cache: DubbingCacheStore(rootURL: directory.appendingPathComponent("cache")), speech: Speech()) else { throw CancellationError() }
        let session = Session()
        session.mediaURL = directory.appendingPathComponent("fixture.mp4")
        session.scriptDraftMediaURL = session.mediaURL
        session.srtURL = directory.appendingPathComponent("working.srt")
        let original = [cue(1, 0, 2, "The little cot is sleeping."), cue(2, 3, 5, "See you later.")]
        let candidate = [cue(1, 0.1, 2.1, "The little cat is sleeping."), original[1]]
        session.segments = original
        try SRTDocument.renderSRT(original).write(to: session.srtURL!, atomically: true, encoding: .utf8)
        let controller = SubtitleComparisonController(session: session, defaults: defaults)
        controller.dubbingOverride = dubbing
        controller.open(source: .audio)
        controller.speechScanOverride = { _, output, _ in
            try await Task.sleep(for: .milliseconds(30))
            try SRTDocument.renderSRT(candidate).write(to: output, atomically: true, encoding: .utf8)
        }
        controller.runAudio(offline: false)
        try check(session.isComparingSubtitles, "comparison did not publish its own busy state")
        try await drain(controller)
        try check(!session.isComparingSubtitles, "comparison busy state was not released")
        try check(controller.phase == .review && session.segments == original && !session.history.canUndo, "candidate mutated transcript")
        try check(SubtitleCreateJobFinisher.parseSRTFile(session.srtURL!) == original, "staging touched working SRT")
        controller.candidateIDs = [0]
        controller.applyChoices()
        try await drain(controller)
        try check(session.segments.map(\.text) == candidate.map(\.text), "choice was not committed")
        try check(session.history.undo(current: session.segments) == original, "Undo failed")
        session.segments = original
        controller.open(source: .audio)
        controller.runAudio(offline: false)
        session.segments = [cue(1, 0, 2, "Manual edit.")]
        try await drain(controller)
        try check(session.segments[0].text == "Manual edit.", "stale snapshot overwritten")
        controller.dismiss()
        session.segments = original
        controller.open(source: .ocr)
        controller.receiveOCR(SubtitleOCRResult(segments: candidate, language: "en", sampledFrames: 10,
            recognitionRequests: 5, frameSeconds: 0, recognitionSeconds: 0, firstRecognitionSeconds: 0))
        try await drain(controller)
        try check(controller.phase == .review && session.segments == original, "OCR candidate mutated transcript")
        controller.dismiss()
        controller.noteCompletion(.audio)
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "audio completion offered OCR")
        controller.noteCompletion(.ocr)
        controller.presentOfferIfEligible()
        try check(controller.phase == .offer && session.subtitleComparisonPresented && controller.source == .audio, "OCR completion did not offer audio")
        controller.continueOffer()
        try check(controller.phase == .audio && !controller.isRunning && session.segments == original, "OCR offer started recognition or changed subtitles")
        controller.dismiss()
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "offer looped after dismissal")
        session.isApplyingTranscriptLayout = true
        controller.noteCompletion(.ocr)
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "busy session showed OCR offer")
        controller.noteCompletion(.audio)
        session.isApplyingTranscriptLayout = false
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "audio completion kept a stale OCR offer")
        controller.suppressOffers = true
        controller.noteCompletion(.ocr)
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "suppressed offer appeared")
        controller.open(source: .audio)
        try check(session.subtitleComparisonPresented, "suppressed offers blocked manual comparison")
        controller.dismiss()
        controller.suppressOffers = false
        controller.open(source: .audio)
        controller.runAudio(offline: false)
        controller.dismiss()
        try await drain(controller)
        try check(session.segments == original && !session.subtitleComparisonPresented, "cancel changed transcript")
        session.scriptText = "The little cat is sleeping.\nSee you later."
        controller.applyOriginalScript()
        try await drain(controller)
        try check(session.segments.map(\.timing) == original.map(\.timing), "script changed timing")
        try check(session.segments.map(\.text).joined().filter { !$0.isWhitespace }
            == session.scriptText.filter { !$0.isWhitespace }, "script wording lost")
        try check(session.history.undo(current: session.segments) == original, "script Undo failed")
        session.segments = original
        session.scriptText = "A completely unrelated sentence."
        controller.applyOriginalScript()
        try await drain(controller)
        try check(session.segments == original && controller.phase == .message, "script mismatch invented timing")
        controller.dismiss()
        session.mediaURL = directory.appendingPathComponent("fixture.m4a")
        controller.noteCompletion(.audio)
        controller.presentOfferIfEligible()
        try check(!session.subtitleComparisonPresented, "audio-only offered OCR")
        // Reproduce an OCR/restored Chinese subtitle context on English audio.
        // The engine spy must receive auto, and completion must reflect the new
        // transcript rather than the old project's language.
        session.whisperDraftMediaURL = session.mediaURL
        session.sourceLang = "zh"
        let speech = SubtitleWhisperCreateController(session: session)
        var requestLanguage: String?
        speech.speechRunOverride = { media, language, _ in
            requestLanguage = language
            await session.runner.runTask(title: "Fixture speech") {
                try SRTDocument.renderSRT(candidate).write(to: ProjectBackupStore.coLocatedSRT(for: media), atomically: true, encoding: .utf8)
            }
        }
        speech.run()
        let deadline = Date().addingTimeInterval(10)
        while (requestLanguage == nil || session.isWhisperJobInFlight) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try check(requestLanguage == "auto" && !session.isWhisperJobInFlight && session.whisperComplete,
            "OCR/restored language leaked into speech recognition")
        try check(session.sourceLang == "en" && session.segments.map(\.text) == candidate.map(\.text),
            "speech completion kept the previous subtitle language")
        print("SPEECH_LANGUAGE_SMOKE_OK previous=zh request=auto completed=en noKey=true noAPI=true")
        print("COMPARISON_SMOKE_OK staging=private OCR=review choice=explicit undo=restored stale=kept cancel=kept offers=OCRtoAudioOnly staleOffer=cleared suppress=manualStillAvailable script=canonical cueTimes=preserved mismatch=rejected noKey=true noAPI=true")
    }
}
