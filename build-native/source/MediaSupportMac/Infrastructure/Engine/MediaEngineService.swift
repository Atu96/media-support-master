import Foundation

@MainActor
final class MediaEngineService: ObservableObject, MediaEngineServing {
    static let shared = MediaEngineService()

    let runner = EngineRunner()

    var logLines: [String] { runner.logLines }
    var isRunning: Bool { runner.isRunning }

    private init() {}

    func refreshStatus() -> EngineStatus {
        AppPaths.engineStatus()
    }

    func runCheckEngines() async {
        await runner.run(ToolsBridge.checkEnginesJob())
    }

    func runWhisperSRT(for mediaURL: URL, sourceLang: String) async {
        let model = GroqModelPreferences.selectedSpeechModel
        let output = ProjectBackupStore.coLocatedSRT(for: mediaURL)
        await runner.runTask(
            title: "Chép lời Groq · \(model.shortLabel) — \(mediaURL.lastPathComponent)"
        ) {
            try await GroqSpeechService.transcribeToSRT(
                mediaURL: mediaURL,
                outputURL: output,
                sourceLanguage: sourceLang,
                model: model,
                wrapStyle: SubtitleWrapStyle.load()
            ) { line in
                Task { @MainActor in
                    self.runner.appendLog(line)
                }
            }
        }
    }

    func runOfflineWhisperSRT(for mediaURL: URL, sourceLang: String) async {
        let output = ProjectBackupStore.coLocatedSRT(for: mediaURL)
        await runner.runTask(
            title: "Chép lời Offline · Whisper V3 Turbo — \(mediaURL.lastPathComponent)"
        ) {
            try await OfflineWhisperService.transcribeToSRT(
                mediaURL: mediaURL,
                outputURL: output,
                sourceLanguage: sourceLang,
                wrapStyle: SubtitleWrapStyle.load()
            ) { line in
                Task { @MainActor in
                    self.runner.appendLog(line)
                }
            }
        }
    }

    func runScriptAlignSRT(
        for mediaURL: URL,
        scriptFile: URL,
        language: ScriptAlignmentLanguage
    ) async {
        await runner.run(
            ToolsBridge.scriptAlignSRTJob(
                for: mediaURL,
                scriptFile: scriptFile,
                language: language
            )
        )
    }

    func runDetectMediaLanguage(for mediaURL: URL) async {
        await runner.run(ToolsBridge.detectMediaLanguageJob(for: mediaURL))
    }

    func runTranslateSRT(
        input: URL,
        output: URL,
        targetLang: String,
        sourceLang: String,
        mode: SubtitleTranslationMode,
        mediaURL: URL?
    ) async {
        switch mode {
        case .appleLocal:
            await runner.runTask(title: "Dịch SRT (Apple Local) → \(targetLang)") {
                try await AppleSRTTranslator.translate(
                    input: input,
                    output: output,
                    targetLang: targetLang,
                    sourceLang: sourceLang,
                    mediaURL: mediaURL
                ) { line in
                    Task { @MainActor in
                        self.runner.appendLog(line)
                    }
                }
            }
        case .gemini, .groq:
            guard mode == .gemini ? GeminiCredentialStore.hasKey : GroqCredentialStore.hasKey else {
                runner.appendLog("❌ Thiếu \(mode.label) key — mở Cài đặt để nhập key")
                return
            }
            await runner.runTask(title: "Dịch SRT (\(mode.label)) → \(targetLang)") {
                try await CloudAIService.translateSRT(
                    input: input,
                    output: output,
                    targetLanguage: targetLang,
                    sourceLanguage: sourceLang,
                    provider: mode
                ) { line in
                    Task { @MainActor in
                        self.runner.appendLog(line)
                    }
                }
            }
        }
    }

    func runBurnSRTVideo(video: URL, srt: URL, output: URL, style: SubtitleBurnStyle) async {
        await runner.run(ToolsBridge.burnSRTVideoJob(video: video, srt: srt, output: output, style: style))
    }

    func runExportSRTFCPXML(srt: URL, output: URL, style: SubtitleBurnStyle) async {
        await runner.run(ToolsBridge.exportSRTFCPXMLJob(srt: srt, output: output, style: style))
    }

    func translatedOutputURL(for input: URL, targetLang: String) -> URL {
        ToolsBridge.translatedOutputURL(for: input, targetLang: targetLang)
    }

    func clearLog() {
        runner.clearLog()
    }
}
