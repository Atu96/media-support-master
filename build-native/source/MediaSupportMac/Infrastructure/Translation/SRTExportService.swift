import AppKit
import Foundation

enum SRTExportService {
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func write(_ text: String, nextTo url: URL, extension ext: String) throws -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let out = dir.appendingPathComponent("\(base).\(ext)")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Mở gói `{tên}/` — ưu tiên chọn SRT, rồi video.
    static func revealExportBundle(for media: URL, targetLang: String? = nil) {
        let srt = ProjectBackupStore.packageDeliverableURL(
            for: media,
            targetLang: targetLang,
            extension: "srt"
        )
        if FileManager.default.fileExists(atPath: srt.path) {
            revealInFinder(srt)
            return
        }

        let bundle = ProjectBackupStore.resolvedExportBundleDir(for: media)
            ?? ProjectBackupStore.exportBundleDir(for: media)
        let video = ProjectBackupStore.bundleMediaURL(for: media)
        if FileManager.default.fileExists(atPath: video.path) {
            revealInFinder(video)
            return
        }
        if FileManager.default.fileExists(atPath: bundle.path) {
            revealInFinder(bundle)
            return
        }
        revealInFinder(media)
    }
}