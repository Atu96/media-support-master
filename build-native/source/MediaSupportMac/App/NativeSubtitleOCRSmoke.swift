import Foundation

enum NativeSubtitleOCRSmoke {
    static func run(directory: URL) async throws {
        let result = try await SubtitleOCRService.scan(media: directory.appendingPathComponent("subtitles.mp4"),
                                                       region: .lower) { _, _ in }
        let srt = SRTDocument.renderSRT(result.segments)
        guard result.segments.count == 2, SRTDocument.parseSegments(srt).count == 2, result.language == "en" else {
            throw SubtitleOCRError.noText
        }
        try srt.write(to: directory.appendingPathComponent("ocr-result.srt"), atomically: true, encoding: .utf8)
        print("OCR_SMOKE_OK local=true autoLanguage=\(result.language) cues=\(result.segments.count) frames=\(result.sampledFrames) requests=\(result.recognitionRequests) srt=ready")
        print(String(format: "OCR_TIMING frame=%.3fs recognition=%.3fs firstRecognition=%.3fs",
                     result.frameSeconds, result.recognitionSeconds, result.firstRecognitionSeconds))
    }
}
