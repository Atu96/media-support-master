import Foundation

/// Hợp đồng gọi engine Tools — Presentation chỉ nói chuyện qua protocol này.
@MainActor
protocol MediaEngineServing: AnyObject {
    var runner: EngineRunner { get }
    var logLines: [String] { get }
    var isRunning: Bool { get }

    func refreshStatus() -> EngineStatus
    func runCheckEngines() async
    func runWhisperSRT(for mediaURL: URL, sourceLang: String) async
    func runOfflineWhisperSRT(for mediaURL: URL, sourceLang: String) async
    func runScriptAlignSRT(
        for mediaURL: URL,
        scriptFile: URL,
        language: ScriptAlignmentLanguage
    ) async
    func runDetectMediaLanguage(for mediaURL: URL) async
    func runTranslateSRT(
        input: URL,
        output: URL,
        targetLang: String,
        sourceLang: String,
        mode: SubtitleTranslationMode,
        mediaURL: URL?
    ) async
    func runBurnSRTVideo(video: URL, srt: URL, output: URL, style: SubtitleBurnStyle) async
    func runExportSRTFCPXML(srt: URL, output: URL, style: SubtitleBurnStyle) async
    func translatedOutputURL(for input: URL, targetLang: String) -> URL
    func clearLog()
}
