import Foundation

enum TranscriptVariant: String, CaseIterable, Identifiable, Sendable {
    case original
    case translated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Gốc"
        case .translated: "Đã dịch"
        }
    }
}

@MainActor
final class SubtitleViewModel: ObservableObject {
    @Published var mediaURL: URL? {
        didSet {
            if oldValue != mediaURL {
                layoutReflow.cancel()
                ocrCreate.cancelIfMediaChanged(to: mediaURL)
                comparison.invalidate()
                timelineMarkers = mediaURL.map { TimelineMarkerPolicy.normalized(ProjectBackupStore.load(for: $0)?.markers ?? []) } ?? []
            }
        }
    }
    @Published var timelineMarkers: [TimelineMarker] = []
    /// Media đang chọn ở tab Tạo sub tự động — tách khỏi dự án active.
    @Published var whisperDraftMediaURL: URL?
    /// Media đang chọn ở tab Khớp văn bản gốc.
    @Published var scriptDraftMediaURL: URL?
    @Published var requestModuleTab: SubtitleModuleTab?
    @Published var srtURL: URL?
    @Published var targetLang = "vi"
    @Published var sourceLang = "auto"

    @Published var segments: [SRTSegment] = [] {
        didSet {
            if oldValue != segments {
                layoutReflow.cancel()
                ocrCreate.cancelIfSessionEdited()
                comparison.invalidate()
            }
        }
    }
    @Published var whisperComplete = false
    @Published var translateComplete = false
    @Published var activeTranscriptVariant: TranscriptVariant = .original {
        didSet {
            if oldValue != activeTranscriptVariant {
                layoutReflow.cancel()
                ocrCreate.cancelIfSessionEdited()
                comparison.invalidate()
            }
        }
    }
    @Published var sessionRestored = false
    @Published var completionSummary = ""
    @Published var transcriptSummary = ""
    @Published var isSummarizing = false
    @Published var exportMessage = ""
    @Published var burnStyle = SubtitleBurnStyle.load() { didSet { if oldValue != burnStyle { comparison.invalidate() } } }
    @Published var wrapStyle = SubtitleWrapStyle.load() { didSet { if oldValue != wrapStyle { comparison.invalidate() } } }
    @Published private var isReflowingTranscript = false
    @Published var isComparingSubtitles = false
    var isApplyingTranscriptLayout: Bool {
        get { isReflowingTranscript || isComparingSubtitles }
        set { isReflowingTranscript = newValue }
    }
    /// Dòng sub đang chọn (tua preview) — overlay hiện đúng text dòng này khi pause.
    @Published var previewFocusSegmentID: Int?
    /// Text đang gõ (Enter xuống dòng) — preview cập nhật realtime trước khi commit.
    @Published var liveEditDraft: (id: Int, text: String)? {
        didSet { if oldValue?.id != liveEditDraft?.id || oldValue?.text != liveEditDraft?.text { comparison.invalidate() } }
    }
    @Published var burnMessage = ""
    @Published var scriptText = ""
    @Published var scriptAlignmentLanguage = ScriptAlignmentLanguage.load() {
        didSet {
            scriptAlignmentLanguage.persist()
            if scriptAlignmentLanguage == .auto {
                refreshScriptLanguageDetection()
            }
        }
    }
    @Published private(set) var scriptDetectedLanguage: ScriptAlignmentLanguage?
    /// Progress create-tab — controller được ghi; View đọc qua facade.
    @Published var scriptAlignProgressPercent = 0
    @Published var whisperProgressPercent = 0
    /// Giữ overlay % tới khi nạp xong sub (engine thoát sớm hơn bước parse UI).
    @Published var isWhisperJobInFlight = false
    /// Align kịch bản — giữ % tới khi có cue (tránh treo/mất overlay khi process thoát).
    @Published var isScriptAlignJobInFlight = false
    // Setter internal — extension files (+Edit / +Translate / +Export) cùng module.
    @Published var translateProgressCurrent = 0
    @Published var translateProgressTotal = 0
    @Published var translateProgressStage = ""
    @Published var canUndoEdit = false
    @Published var canRedoEdit = false
    @Published var exportDeliverySignal: ExportDeliverySignal?
    @Published var cloudAlert: CloudAIErrorAlert?
    @Published var subtitleComparisonPresented = false
    @Published var subtitleEvidenceCompletion: UUID?

    let engine: MediaEngineServing
    let preview = AVPreviewService.shared
    private let coordinator: AppCoordinator

    /// Mã thực sự gửi vào Whisper/align. `auto` chỉ là lựa chọn UI, không đi xuống shell.
    var effectiveScriptAlignmentLanguage: ScriptAlignmentLanguage {
        scriptAlignmentLanguage == .auto
            ? (scriptDetectedLanguage ?? ScriptLanguageDetector.detect(from: scriptText) ?? .english)
            : scriptAlignmentLanguage
    }

    var scriptLanguageDetectionMessage: String? {
        guard scriptAlignmentLanguage == .auto, let detected = scriptDetectedLanguage else { return nil }
        return "Đã nhận diện: \(detected.label)"
    }

    func refreshScriptLanguageDetection() {
        scriptDetectedLanguage = ScriptLanguageDetector.detect(from: scriptText)
    }
    /// Shared với extension files (+Session / +Export / +Translate / +Edit).
    let preferences = SubtitlePreferences.shared
    let backupPrefs = BackupPreferences.shared
    /// Edit transcript / undo / wrap / timing API — tách khỏi create/export.
    let transcriptStore = SubtitleTranscriptStore()
    var persistEditTask: Task<Void, Never>?
    var persistSessionTask: Task<Void, Never>?
    lazy var layoutReflow = SubtitleLayoutReflowController { [weak self] isRunning in
        self?.isApplyingTranscriptLayout = isRunning
    }

    /// Controllers tab Tạo sub — logic tách file trong `Create/`.
    lazy var whisperCreate = SubtitleWhisperCreateController(session: self)
    lazy var scriptCreate = SubtitleScriptCreateController(session: self)
    lazy var ocrCreate = SubtitleOCRCreateController(session: self)
    lazy var comparison = SubtitleComparisonController(session: self)

    init(coordinator: AppCoordinator) {
        self.engine = MediaEngineService.shared
        self.coordinator = coordinator
        syncPreferencesContext()
    }

    func refreshEngineStatus() {
        coordinator.refreshEngineStatus()
    }

    var coordinatorEngineIsReady: Bool {
        coordinator.engineStatus.isReady
    }

    func openCloudKeySettings() {
        guard preferences.translationMode != .appleLocal else { return }
        coordinator.openSettings(
            tab: preferences.translationMode == .gemini ? .gemini : .groq
        )
    }

    func openGroqSettings() {
        coordinator.openSettings(tab: .groq)
    }

    func presentLastCloudAlertIfNeeded() {
        cloudAlert = runner.lastCloudAlert
    }

    func presentWhisperCloudAlertIfNeeded() {
        guard let alert = runner.lastCloudAlert else { return }
        let offlineReady = OfflineWhisperModelManager.isModelReady
        cloudAlert = CloudAIErrorAlert(
            title: alert.title,
            message: alert.message + (offlineReady
                ? " Bạn có thể dùng Whisper Turbo Offline ngay."
                : " Có thể tải Whisper Turbo Offline trong Cài đặt để dự phòng."),
            settingsTab: offlineReady ? nil : .offlineWhisper,
            offersOfflineWhisper: offlineReady
        )
    }

    func handleCloudAlertAction(_ alert: CloudAIErrorAlert) {
        if alert.offersOfflineWhisper {
            whisperCreate.runOffline()
            return
        }
        guard let settingsTab = alert.settingsTab else { return }
        coordinator.openSettings(tab: settingsTab)
    }

    // runWhisper / runScriptAlign — Create/
    func runWhisper() {
        whisperCreate.run()
    }

    func runWhisperOffline() {
        whisperCreate.runOffline()
    }

    func runScriptAlign() {
        if whisperComplete, !segments.isEmpty, activeTranscriptVariant == .original,
           mediaURL == scriptDraftMediaURL {
            comparison.applyOriginalScript()
            return
        }
        scriptCreate.run()
    }

    func didCompleteSubtitleSource(_ source: SubtitleEvidenceSource) {
        comparison.noteCompletion(source)
    }

    func cancelComparisonOCR() { ocrCreate.cancel() }
}

// MARK: - Create session (facade for Create/ controllers)

extension SubtitleViewModel: SubtitleCreateSession {}
extension SubtitleViewModel: SubtitleComparisonSession {}
