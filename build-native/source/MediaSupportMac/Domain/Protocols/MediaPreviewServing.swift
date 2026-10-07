import Foundation

/// Hợp đồng preview media — Phase 0.2+ mở rộng timeline, SRT overlay.
@MainActor
protocol MediaPreviewServing: AnyObject {
    var currentURL: URL? { get }
    var isLoaded: Bool { get }

    func load(url: URL)
    func play()
    func pause()
    func togglePlayPause()
    func seek(seconds: Double)
    func clear()
}