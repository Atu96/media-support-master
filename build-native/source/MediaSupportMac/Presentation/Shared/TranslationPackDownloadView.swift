import SwiftUI
import Translation

/// Dùng translationTask của hệ thống để tải gói ngôn ngữ Apple (hiện UI macOS).
struct TranslationPackDownloadView: View {
    @ObservedObject var manager = AppleLanguagePackManager.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(manager.activeDownload) { session in
                guard let config = manager.activeDownload else { return }
                let source = config.source?.languageCode?.identifier ?? "?"
                let target = config.target?.languageCode?.identifier ?? "vi"
                do {
                    try await session.prepareTranslation()
                    manager.finishDownload(success: true, source: source, target: target)
                } catch {
                    manager.downloadMessage = "Tải gói thất bại: \(error.localizedDescription)"
                    manager.finishDownload(success: false, source: source, target: target)
                }
            }
    }
}