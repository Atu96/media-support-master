import SwiftUI
import UniformTypeIdentifiers

/// Màn mở **video + SRT có sẵn** của tab Sửa phụ đề — không chạy Whisper.
struct SubtitleOpenExistingPairPanel: View {
    @ObservedObject var viewModel: SubtitleViewModel
    var onOpen: (() -> Void)? = nil

    @State private var pendingMediaName: String?
    @State private var pendingSRTName: String?
    @State private var pendingMediaURL: URL?
    @State private var pendingSRTURL: URL?
    @State private var statusText = "SRT cùng tên, cùng thư mục: chỉ cần chọn video."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentBlue.opacity(0.95),
                                    AppTheme.accentCyan.opacity(0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: AppTheme.accentBlue.opacity(0.22), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("Sửa phụ đề có sẵn")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.headlineText)
                        Text("KHÔNG CHÉP LẠI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.accentBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.accentBlue.opacity(0.09), in: Capsule())
                    }
                    Text("Chọn một cặp riêng biệt để vào thẳng timeline chỉnh sửa.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                dropSlot(
                    title: "Video",
                    icon: "film",
                    filename: pendingMediaName,
                    placeholder: "Thả video hoặc chọn từ máy",
                    kind: .media
                ) { url in
                    acceptMedia(url)
                }

                dropSlot(
                    title: "SRT",
                    icon: "doc.text",
                    filename: pendingSRTName,
                    placeholder: "Thả file .srt",
                    kind: .srt
                ) { url in
                    pendingSRTURL = url
                    pendingSRTName = url.lastPathComponent
                    statusText = pendingMediaURL == nil
                        ? "Đã nhận SRT — chọn thêm video để mở timeline."
                        : "Đã đủ video và SRT — sẵn sàng mở để chỉnh."
                }
            }

            HStack(spacing: 9) {
                Image(systemName: pendingSRTURL == nil ? "sparkles" : "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pendingSRTURL == nil ? AppTheme.accentBlue : AppTheme.accentGreen)
                Text(statusText)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
                Spacer(minLength: 8)

                AppPillButton(
                    title: "Mở để chỉnh",
                    icon: "arrow.right.circle.fill",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: !canOpenPair
                ) {
                    openPair()
                }

                if pendingMediaURL != nil || pendingSRTURL != nil {
                    AppPillButton(
                        title: "Xóa chọn",
                        icon: "xmark",
                        tint: AppTheme.mutedText,
                        filled: false
                    ) {
                        clearPending()
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.56), lineWidth: 0.7)
            }
        }
        .padding(22)
        .frame(maxWidth: 780, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.50), AppTheme.accentCyan.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.74), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .shadow(color: AppTheme.accentBlue.opacity(0.09), radius: 24, y: 10)
    }

    private var canOpenPair: Bool {
        pendingMediaURL != nil && pendingSRTURL != nil
    }

    private func acceptMedia(_ media: URL) {
        pendingMediaURL = media
        pendingMediaName = media.lastPathComponent

        // Đường tắt được quảng bá ngay trên thẻ: video + SRT cùng tên/cùng thư mục.
        let coLocated = ProjectBackupStore.coLocatedSRT(for: media)
        if FileManager.default.fileExists(atPath: coLocated.path) {
            viewModel.openMediaAndExistingSRT(media: media, srt: coLocated)
            clearPending()
            onOpen?()
            return
        }

        statusText = pendingSRTURL == nil
            ? "Không thấy SRT cùng tên — chọn thêm file SRT."
            : "Đã đủ video và SRT — sẵn sàng mở để chỉnh."
    }

    private func openPair() {
        guard let media = pendingMediaURL, let srt = pendingSRTURL else { return }
        viewModel.openMediaAndExistingSRT(media: media, srt: srt)
        clearPending()
        onOpen?()
    }

    private func clearPending() {
        pendingMediaURL = nil
        pendingSRTURL = nil
        pendingMediaName = nil
        pendingSRTName = nil
        statusText = "SRT cùng tên, cùng thư mục: chỉ cần chọn video."
    }

    private func dropSlot(
        title: String,
        icon: String,
        filename: String?,
        placeholder: String,
        kind: FileDropKind,
        onURL: @escaping (URL) -> Void
    ) -> some View {
        AppFileDropField(
            label: "\(icon == "film" ? "1" : "2"). \(title)",
            placeholder: placeholder,
            filename: filename,
            chooseTitle: filename == nil ? "Chọn \(title.lowercased())" : "Đổi",
            dropKind: kind,
            onChoose: {
                switch kind {
                case .srt:
                    FilePickerHelper.pickFile(allowedTypes: [FilePickerHelper.srtType]) {
                        onURL($0)
                    }
                case .media, .video:
                    FilePickerHelper.pickFile(allowedTypes: FilePickerHelper.mediaTypes) {
                        onURL($0)
                    }
                case .subtitleSource:
                    FilePickerHelper.pickFile(
                        allowedTypes: FilePickerHelper.mediaTypes + [FilePickerHelper.srtType]
                    ) {
                        onURL($0)
                    }
                }
            },
            onDrop: onURL
        )
        .frame(maxWidth: .infinity)
    }
}
