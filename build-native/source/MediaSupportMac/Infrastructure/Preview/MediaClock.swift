import Foundation

/// Đồng hồ media — **một nguồn sự thật** cho playhead / seek.
///
/// Hiện bọc `AVPreviewService.shared`. Timeline / highlight cue sau này
/// chỉ đọc `currentTime` + `seek` qua đây, không tự giữ clock thứ hai.
@MainActor
enum MediaClock {
    static var preview: AVPreviewService { AVPreviewService.shared }

    static var currentTime: Double { preview.currentTime }
    static var duration: Double { preview.duration }
    static var isPlaying: Bool { preview.isPlaying }
    static var currentURL: URL? { preview.currentURL }

    static func seek(seconds: Double, playAfter: Bool = false) {
        preview.seek(seconds: seconds, playAfter: playAfter)
    }

    static func seekForEdit(seconds: Double) {
        preview.seekForEdit(seconds: seconds)
    }
}
