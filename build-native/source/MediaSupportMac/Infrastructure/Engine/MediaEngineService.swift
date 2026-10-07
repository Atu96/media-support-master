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
        language: ScriptAlignmentLanguage,
        outputURL: URL
    ) async {
        // Keep the established Japanese MeCab alignment path.
        if language == .japanese {
            await runner.run(ToolsBridge.scriptAlignSRTJob(for:mediaURL,scriptFile:scriptFile,
                                                          language:language,outputURL:outputURL))
            return
        }
        await runner.runTask(title:"Align kịch bản — \(mediaURL.lastPathComponent)") {
            try await NativeScriptAlignmentService.align(media:mediaURL,scriptFile:scriptFile,output:outputURL,language:language.rawValue) { line in
                Task { @MainActor in self.runner.appendLog(line) }
            }
        }
    }

    func runDetectMediaLanguage(for mediaURL: URL) async {
        await runner.runTask(title:"Nhận diện ngôn ngữ — \(mediaURL.lastPathComponent)") {
            let record=try await NativeWhisperRuntime.detectLanguage(media:mediaURL) { line in
                Task { @MainActor in self.runner.appendLog(line) }
            }
            try MediaLanguageRecord.save(record,near:mediaURL)
            ProjectBackupStore.recordDetectedLanguage(record,for:mediaURL)
            self.runner.appendLog("✓ \(record.language)")
        }
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
        await runner.runTask(title: "Xuất FCPXML — \(srt.lastPathComponent)") {
            let worker = Task.detached(priority: .utility) {
                let template = try MotionTemplateInstaller.resolveOrInstall()
                let text = try String(contentsOf: srt, encoding: .utf8)
                let xml = try NativeFCPXMLExporter.render(segments: SRTDocument.parseSegments(text),
                    name: srt.deletingPathExtension().lastPathComponent, style: style, templateURL: template)
                try Task.checkCancellation()
                try xml.write(to: output, atomically: true, encoding: .utf8)
            }
            try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        }
    }

    func translatedOutputURL(for input: URL, targetLang: String) -> URL {
        ToolsBridge.translatedOutputURL(for: input, targetLang: targetLang)
    }

    func clearLog() {
        runner.clearLog()
    }
}
