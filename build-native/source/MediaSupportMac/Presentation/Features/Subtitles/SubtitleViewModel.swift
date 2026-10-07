import Foundation

enum TranscriptVariant: String, CaseIterable, Identifiable {
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
        didSet { if oldValue != mediaURL { layoutReflow.cancel() } }
    }
    /// Media đang chọn ở tab Tạo sub tự động — tách khỏi dự án active.
    @Published var whisperDraftMediaURL: URL?
    /// Media đang chọn ở tab Khớp văn bản gốc.
    @Published var scriptDraftMediaURL: URL?
    @Published var requestModuleTab: SubtitleModuleTab?
    @Published var srtURL: URL?
    @Published var targetLang = "vi"
    @Published var sourceLang = "auto"

    @Published var segments: [SRTSegment] = [] {
        didSet { if oldValue != segments { layoutReflow.cancel() } }
    }
    @Published var whisperComplete = false
    @Published var translateComplete = false
    @Published var activeTranscriptVariant: TranscriptVariant = .original {
        didSet { if oldValue != activeTranscriptVariant { layoutReflow.cancel() } }
    }
    @Published var sessionRestored = false
    @Published var completionSummary = ""
    @Published var transcriptSummary = ""
    @Published var isSummarizing = false
    @Published var exportMessage = ""
    @Published var burnStyle = SubtitleBurnStyle.load()
    @Published var wrapStyle = SubtitleWrapStyle.load()
    @Published var isApplyingTranscriptLayout = false
    /// Dòng sub đang chọn (tua preview) — overlay hiện đúng text dòng này khi pause.
    @Published var previewFocusSegmentID: Int?
    /// Text đang gõ (Enter xuống dòng) — preview cập nhật realtime trước khi commit.
    @Published var liveEditDraft: (id: Int, text: String)?
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
        scriptCreate.run()
    }
}

// MARK: - Create session (facade for Create/ controllers)

extension SubtitleViewModel: SubtitleCreateSession {}
