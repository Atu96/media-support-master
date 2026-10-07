import SwiftUI

struct MediaPreviewView: View {
    @ObservedObject private var preview = AVPreviewService.shared
    @StateObject private var viewModel = PreviewViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppSectionHeader(title: "Trình phát")

            AppDropZone(kind: .video, onURLs: { urls in
                if let url = urls.first { viewModel.load(url: url) }
            }) {
                AppCard(title: "Xem trước video", subtitle: nil) {
                    if preview.isLoaded {
                        AVPlayerContainerView(player: preview.player, showsBuiltInControls: false)
                            .frame(minHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldRadius, style: .continuous))
                        PreviewTransportBar(preview: preview)
                        Text(preview.currentURL?.lastPathComponent ?? "")
                            .font(AppFont.mono)
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(1)
                    } else {
                        placeholder
                    }

                    AppActionRow(
                        primaryTitle: "Chọn video",
                        primaryIcon: "folder",
                        onPrimary: { viewModel.pickAndLoad() },
                        secondary: [
                            AppSecondaryAction(
                                title: "Cửa sổ riêng",
                                icon: "macwindow",
                                disabled: !preview.isLoaded
                            ) {
                                viewModel.openDetachedWindow()
                            }
                        ]
                    )
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            AppFieldSurface(radius: AppTheme.cardRadius)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accentBlue.opacity(0.45))
                Text("Kéo thả video vào đây")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .frame(minHeight: 300)
    }

}