import Foundation

/// Factory job gọi shell wrapper — không import SwiftUI.
enum ToolsBridge {
    static func whisperSRTJob(for mediaURL: URL, wrap: SubtitleWrapStyle = .load()) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_whisper_srt.sh").path
        let w = wrap.clamped()
        let font = SubtitleBurnStyle.load().fontSize
        let maxLine = SubtitleWrapStyle.effectiveMaxCharsPerLine(base: w.maxCharsPerLine, fontSize: font)
        let maxBlock = max(maxLine, maxLine * max(1, min(3, w.maxLines)))
        return EngineJob(
            title: "Chép lời Whisper — \(mediaURL.lastPathComponent)",
            executable: "/bin/zsh",
            arguments: [script, mediaURL.path],
            environment: [
                // Effective = chữ/dòng × scale cỡ chữ (font lớn → siết).
                "MSM_MAX_LINE_CHARS": String(maxLine),
                "MSM_MAX_BLOCK_CHARS": String(maxBlock),
                "MSM_MAX_LINES": String(w.maxLines),
                "MSM_TOP_LINE_RATIO": w.topLineRatio.rawValue,
                "PYTHONUNBUFFERED": "1",
            ],
            workingDirectory: AppPaths.appRoot
        )
    }

    static func scriptAlignSRTJob(
        for mediaURL: URL,
        scriptFile: URL,
        language: ScriptAlignmentLanguage
    ) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_tao_srt_kichban.sh").path
        let w = SubtitleWrapStyle.load().clamped()
        let font = SubtitleBurnStyle.load().fontSize
        let maxLine = SubtitleWrapStyle.effectiveMaxCharsPerLine(base: w.maxCharsPerLine, fontSize: font)
        let maxBlock = max(maxLine, maxLine * max(1, min(3, w.maxLines)))
        return EngineJob(
            title: "Align kịch bản — \(mediaURL.lastPathComponent)",
            executable: "/bin/zsh",
            arguments: [script, mediaURL.path, scriptFile.path, language.rawValue],
            environment: [
                "MSM_MAX_LINE_CHARS": String(maxLine),
                "MSM_MAX_BLOCK_CHARS": String(maxBlock),
                "MSM_MAX_LINES": String(w.maxLines),
                "MSM_TOP_LINE_RATIO": w.topLineRatio.rawValue,
                "PYTHONUNBUFFERED": "1",
            ],
            workingDirectory: AppPaths.appRoot
        )
    }

    static func detectMediaLanguageJob(for mediaURL: URL) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_detect_media_lang.sh").path
        return EngineJob(
            title: "Detect ngôn ngữ — \(mediaURL.lastPathComponent)",
            executable: "/bin/bash",
            arguments: [script, mediaURL.path],
            environment: [:],
            workingDirectory: AppPaths.appRoot
        )
    }

    static func translateGeminiSRTJob(
        input: URL,
        output: URL,
        targetLang: String,
        sourceLang: String = "auto"
    ) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_translate_srt_gemini.sh").path
        return EngineJob(
            title: "Dịch SRT (Gemini) → \(targetLang)",
            executable: "/bin/bash",
            arguments: [script, input.path, output.path, targetLang, sourceLang],
            environment: ["GEMINI_API_KEY": GeminiCredentialStore.load()],
            workingDirectory: AppPaths.appRoot
        )
    }

    static func checkEnginesJob() -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("check_engines.sh").path
        return EngineJob(
            title: "Kiểm tra engine",
            executable: "/bin/bash",
            arguments: [script],
            environment: [:],
            workingDirectory: AppPaths.appRoot
        )
    }

    static func translatedOutputURL(for input: URL, targetLang: String) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(base)_\(targetLang).srt")
    }

    static func burnSRTVideoJob(
        video: URL,
        srt: URL,
        output: URL,
        style: SubtitleBurnStyle
    ) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_burn_srt_video.sh").path
        var args = [script, video.path, srt.path, "-o", output.path]
        args.append(contentsOf: style.burnCLIArgs)
        return EngineJob(
            title: "Gắn sub — \(video.lastPathComponent)",
            executable: "/bin/bash",
            arguments: args,
            environment: [:],
            workingDirectory: video.deletingLastPathComponent()
        )
    }

    static func exportSRTFCPXMLJob(
        srt: URL,
        output: URL,
        style: SubtitleBurnStyle
    ) -> EngineJob {
        let script = AppPaths.scriptsDir.appendingPathComponent("run_srt_fcpxml.sh").path
        var args = [script, srt.path, output.path]
        args.append(contentsOf: style.fcpxmlCLIArgs)
        return EngineJob(
            title: "Xuất FCPXML — \(srt.lastPathComponent)",
            executable: "/bin/bash",
            arguments: args,
            environment: [:],
            workingDirectory: srt.deletingLastPathComponent()
        )
    }
}
