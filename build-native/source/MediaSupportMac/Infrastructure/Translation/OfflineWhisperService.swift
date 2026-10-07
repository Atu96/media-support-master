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
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaSupport-OfflineWhisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let normalizedLanguage = AppleSRTTranslator.normalizeLangCode(sourceLanguage)
        let transcript = try await NativeWhisperRuntime.transcript(media: mediaURL,
            language: normalizedLanguage, directory: tempDirectory, progress: progress)
        async let speechActivity = detectSpeechActivity(in: tempDirectory.appendingPathComponent("audio.wav"))
        progress("… Sắp xếp phụ đề")
        let style = wrapStyle.clamped()
        let burnStyle = SubtitleBurnStyle.load()
        let previewFrame = VideoPreviewFrame.classify(displaySize: VideoGeometryProbe.displaySize(for: mediaURL))
        let textWidth = Double(previewFrame.referencePixelSize.width) * Double(burnStyle.boxMaxWidthRatio) - 24
        let rawSegments = transcript.segments
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
        try Task.checkCancellation()
        try wrapped.write(to: outputURL, atomically: true, encoding: .utf8)
        progress("MSM_PROGRESS:100")
    }

    private static func detectSpeechActivity(in audioURL: URL) async -> [SpeechActivityInterval] {
        (try? await AppleSpeechActivityDetector.detect(in: audioURL)) ?? []
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
