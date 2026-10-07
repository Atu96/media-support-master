@preconcurrency import AVFoundation
import Foundation

enum OfflineWhisperService {
    static func transcribeToSRT(
        mediaURL: URL,
        outputURL: URL,
        sourceLanguage: String,
        wrapStyle: SubtitleWrapStyle,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        guard OfflineWhisperModelManager.isModelReady else {
            throw OfflineWhisperError.modelNotInstalled
        }
        guard let engineURL = bundledEngineURL else {
            throw OfflineWhisperError.engineMissing
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaSupport-OfflineWhisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let wavURL = tempDirectory.appendingPathComponent("audio.wav")
        progress("MSM_PROGRESS:5")
        progress("… Chuẩn bị âm thanh cho Whisper Offline")
        try await preparePCM16WAV(from: mediaURL, to: wavURL, in: tempDirectory)
        async let speechActivity = detectSpeechActivity(in: wavURL)

        let outputBase = tempDirectory.appendingPathComponent("transcript")
        var arguments = [
            "-m", OfflineWhisperModelManager.modelURL.path,
            "-f", wavURL.path,
            "--output-srt",
            "--output-file", outputBase.path,
            "--threads", "4",
            "--no-gpu",
        ]
        let normalizedLanguage = AppleSRTTranslator.normalizeLangCode(sourceLanguage)
        arguments += ["--language", normalizedLanguage == "auto" ? "auto" : normalizedLanguage]

        progress("MSM_PROGRESS:15")
        progress("… Whisper Turbo đang chép lời offline")
        try await runEngine(engineURL, arguments: arguments)

        let rawSRT = outputBase.appendingPathExtension("srt")
        guard FileManager.default.fileExists(atPath: rawSRT.path) else {
            throw OfflineWhisperError.noTranscript
        }
        let content = try String(contentsOf: rawSRT, encoding: .utf8)
        let blocks = SRTDocument.parse(content)
        guard !blocks.isEmpty else { throw OfflineWhisperError.noTranscript }
        let style = wrapStyle.clamped()
        let burnStyle = SubtitleBurnStyle.load()
        let previewFrame = VideoPreviewFrame.classify(displaySize: VideoGeometryProbe.displaySize(for: mediaURL))
        let textWidth = Double(previewFrame.referencePixelSize.width) * Double(burnStyle.boxMaxWidthRatio) - 24
        let rawSegments = SRTDocument.parseSegments(content)
        let formatted = SubtitleTranscriptPostProcessor.format(
            rawSegments,
            sourceLanguage: sourceLanguage,
            style: style,
            fontSize: burnStyle.fontSize,
            fontName: burnStyle.fontName,
            containerWidth: max(120, textWidth)
        )
        let refined = SpeechTimingRefiner.refine(formatted, using: await speechActivity)
        let wrapped = SRTDocument.renderSRT(refined)
        try wrapped.write(to: outputURL, atomically: true, encoding: .utf8)
        progress("MSM_PROGRESS:100")
    }

    private static func detectSpeechActivity(in audioURL: URL) async -> [SpeechActivityInterval] {
        (try? await AppleSpeechActivityDetector.detect(in: audioURL)) ?? []
    }

    private static var bundledEngineURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("offline-whisper/bin/whisper-cli")
    }

    private static func runEngine(_ executable: URL, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaSupport-Process-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: logURL)
        process.standardError = errorHandle
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: logURL)
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        try? errorHandle.synchronize()
        guard process.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OfflineWhisperError.engineFailed(detail ?? "")
        }
    }

    private static func preparePCM16WAV(
        from mediaURL: URL,
        to wavURL: URL,
        in tempDirectory: URL
    ) async throws {
        let asset = AVURLAsset(url: mediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw OfflineWhisperError.noAudio
        }
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw OfflineWhisperError.cannotPrepareAudio
        }
        let m4aURL = tempDirectory.appendingPathComponent("audio.m4a")
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: m4aURL, as: .m4a)

        let converter = URL(fileURLWithPath: "/usr/bin/afconvert")
        do {
            try await runEngine(
                converter,
                arguments: [
                    m4aURL.path,
                    wavURL.path,
                    "-f", "WAVE",
                    "-d", "LEI16@16000",
                    "-c", "1",
                    "-r", "127",
                ]
            )
        } catch {
            throw OfflineWhisperError.cannotPrepareAudio
        }
    }
}

enum OfflineWhisperError: LocalizedError {
    case modelNotInstalled
    case engineMissing
    case noAudio
    case cannotPrepareAudio
    case engineFailed(String)
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled: "Chưa tải model Whisper Offline trong Cài đặt."
        case .engineMissing: "Thiếu engine Whisper Offline trong app."
        case .noAudio: "Media không có track âm thanh."
        case .cannotPrepareAudio: "Không thể chuẩn bị âm thanh cho Whisper Offline."
        case let .engineFailed(detail):
            detail.isEmpty ? "Whisper Offline chạy thất bại." : "Whisper Offline lỗi: \(detail)"
        case .noTranscript: "Whisper Offline không tạo được phụ đề."
        }
    }
}
