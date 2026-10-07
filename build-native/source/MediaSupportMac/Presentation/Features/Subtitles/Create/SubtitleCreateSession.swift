import Foundation

/// Hợp đồng giữa controller tab Tạo sub và `SubtitleViewModel` (facade).
/// Giữ VM làm session duy nhất — controller không giữ state UI riêng (tránh Combine).
@MainActor
protocol SubtitleCreateSession: AnyObject {
    var mediaURL: URL? { get }
    var whisperDraftMediaURL: URL? { get set }
    var scriptDraftMediaURL: URL? { get set }
    var scriptText: String { get set }
    var scriptAlignmentLanguage: ScriptAlignmentLanguage { get set }
    var effectiveScriptAlignmentLanguage: ScriptAlignmentLanguage { get }
    var sourceLang: String { get set }
    var burnStyle: SubtitleBurnStyle { get }
    var wrapStyle: SubtitleWrapStyle { get }
    var subtitleLayoutContainerWidth: Double { get }

    var segments: [SRTSegment] { get set }
    var srtURL: URL? { get set }
    var whisperComplete: Bool { get set }
    var translateComplete: Bool { get set }
    var activeTranscriptVariant: TranscriptVariant { get set }
    var exportMessage: String { get set }
    var transcriptSummary: String { get set }
    var completionSummary: String { get set }

    var whisperProgressPercent: Int { get set }
    var scriptAlignProgressPercent: Int { get set }
    /// true từ lúc bấm Chép lời → nạp xong sub + hiện 100% (không tắt khi process engine thoát).
    var isWhisperJobInFlight: Bool { get set }
    /// Align kịch bản: giữ overlay % tới khi nạp cue xong.
    var isScriptAlignJobInFlight: Bool { get set }

    var engine: MediaEngineServing { get }
    var runner: EngineRunner { get }
    var preview: AVPreviewService { get }

    func isActiveProject(_ url: URL) -> Bool
    func setMediaURL(_ url: URL)
    func attachPreviewVideo()
    func resetEditHistory()
    func persistProjectSession()
    func syncPreferencesContext()
    func refreshEngineStatus()
    func languageDisplayName(_ code: String) -> String
    func presentLastCloudAlertIfNeeded()
    func presentWhisperCloudAlertIfNeeded()
}
