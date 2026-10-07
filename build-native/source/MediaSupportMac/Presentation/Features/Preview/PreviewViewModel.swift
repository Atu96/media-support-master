import Foundation

@MainActor
final class PreviewViewModel: ObservableObject {
    private let preview: AVPreviewService
    private let coordinator: AppCoordinator

    init() {
        self.preview = AVPreviewService.shared
        self.coordinator = AppCoordinator.shared
    }

    var service: AVPreviewService { preview }

    var currentURL: URL? { preview.currentURL }
    var isLoaded: Bool { preview.isLoaded }
    var isPlaying: Bool { preview.isPlaying }
    var duration: Double { preview.duration }
    var currentTime: Double { preview.currentTime }

    func pickAndLoad() {
        FilePickerHelper.pickFile(allowedTypes: FilePickerHelper.mediaTypes) { url in
            self.preview.load(url: url)
        }
    }

    func load(url: URL) {
        preview.load(url: url)
    }

    func togglePlayPause() { preview.togglePlayPause() }
    func seek(to seconds: Double) { preview.seek(seconds: seconds) }

    func openDetachedWindow() {
        coordinator.openPreviewWindow(url: preview.currentURL)
    }
}