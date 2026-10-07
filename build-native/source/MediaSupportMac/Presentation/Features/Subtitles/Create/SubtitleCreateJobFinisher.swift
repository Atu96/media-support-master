import Foundation

/// Hậu xử lý chung sau Whisper / script-align: ingest vault + parse SRT (off MainActor).
enum SubtitleCreateJobFinisher {
    struct Result: Sendable {
        let srtURL: URL?
        let segments: [SRTSegment]
        /// `"vault"` nếu copy vault thất bại nhưng vẫn parse được SRT cạnh media.
        let warning: String?
    }

    /// Chạy trên background — không đụng UI.
    static func ingestAndParse(coLocatedSRT: URL, media: URL, exitOK: Bool) -> Result {
        guard exitOK, FileManager.default.fileExists(atPath: coLocatedSRT.path) else {
            return Result(srtURL: nil, segments: [], warning: nil)
        }
        do {
            try ProjectBackupStore.ingestTranscript(from: coLocatedSRT, media: media)
        } catch {
            return Result(
                srtURL: coLocatedSRT,
                segments: parseSRTFile(coLocatedSRT),
                warning: "vault"
            )
        }
        let working = ProjectBackupStore.resolvedSRTURL(for: media) ?? coLocatedSRT
        return Result(srtURL: working, segments: parseSRTFile(working), warning: nil)
    }

    static func parseSRTFile(_ url: URL) -> [SRTSegment] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return SRTDocument.parseSegments(content)
    }
}
