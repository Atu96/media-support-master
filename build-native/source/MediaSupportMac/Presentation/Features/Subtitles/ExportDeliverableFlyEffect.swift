import SwiftUI

enum ExportDeliverableKind: String, Equatable {
    case txt
    case srt
    case xml
    case video

    var icon: String {
        switch self {
        case .txt: "doc.text.fill"
        case .srt: "captions.bubble.fill"
        case .xml: "film.fill"
        case .video: "video.fill"
        }
    }

    var tint: Color {
        switch self {
        case .txt: AppTheme.accentBlue
        case .srt: AppTheme.accentGreen
        case .xml: AppTheme.accentOrange
        case .video: AppTheme.accentCyan
        }
    }
}

struct ExportDeliverySignal: Equatable {
    let kind: ExportDeliverableKind
    let fileURL: URL?
    let token: UUID

    init(kind: ExportDeliverableKind, fileURL: URL? = nil) {
        self.kind = kind
        self.fileURL = fileURL
        self.token = UUID()
    }
}

/// Phản hồi xuất file của Timeline: không chặn người dựng, nhưng luôn cho biết
/// file nào vừa xong và có đường mở đúng file đó trong Finder.
struct TimelineExportDeliveryToast: View {
    let signal: ExportDeliverySignal
    let onReveal: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(signal.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("Đã xuất %@", signal.kind.label))
                    .font(.system(size: 12, weight: .bold))
                Text(signal.fileURL?.lastPathComponent ?? "File đã sẵn sàng")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let fileURL = signal.fileURL {
                Button("Mở trong Finder") { onReveal(fileURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Mở Finder và chọn file vừa xuất")
            }
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .buttonStyle(TimelineToolbarButtonStyle())
                .foregroundStyle(AppTheme.mutedText)
                .help("Đóng thông báo")
                .accessibilityLabel("Đóng thông báo")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.overlayRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.overlayRadius, style: .continuous)
                .strokeBorder(AppTheme.tileStrokeStrong.opacity(0.72), lineWidth: AppTheme.controlStrokeWidth)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            L10n.format(
                "Đã xuất %@, %@",
                signal.kind.label,
                signal.fileURL?.lastPathComponent ?? L10n.string("File đã sẵn sàng")
            )
        )
    }
}

private extension ExportDeliverableKind {
    var label: String {
        switch self {
        case .txt: "TXT"
        case .srt: "SRT"
        case .xml: "FCPXML"
        case .video: "video"
        }
    }
}

enum TranscriptToolbarSlot: Hashable {
    case export(ExportDeliverableKind)
    case folder
}

struct TranscriptToolbarFramesKey: PreferenceKey {
    static var defaultValue: [TranscriptToolbarSlot: CGRect] = [:]

    static func reduce(value: inout [TranscriptToolbarSlot: CGRect], nextValue: () -> [TranscriptToolbarSlot: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TranscriptToolbarFrameReporter: View {
    let slot: TranscriptToolbarSlot

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TranscriptToolbarFramesKey.self,
                value: [slot: proxy.frame(in: .named("transcriptExportToolbar"))]
            )
        }
    }
}

/// File bay từ nút xuất → Thư mục, rồi Thư mục sáng xanh.
struct TranscriptExportFlyOverlay: View {
    let signal: ExportDeliverySignal?
    let toolbarFrames: [TranscriptToolbarSlot: CGRect]
    @Binding var folderHighlighted: Bool

    @State private var flyingKind: ExportDeliverableKind?
    @State private var flyProgress: CGFloat = 0
    @State private var flySource = CGRect.zero
    @State private var flyDest = CGRect.zero
    @State private var lastHandledToken: UUID?

    var body: some View {
        GeometryReader { geo in
            if let flyingKind {
                flyingBadge(for: flyingKind)
                    .position(
                        x: flySource.midX + (flyDest.midX - flySource.midX) * flyProgress,
                        y: flySource.midY + (flyDest.midY - flySource.midY) * flyProgress
                    )
                    .scaleEffect(1.05 - flyProgress * 0.1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: signal?.token) { _, token in
            guard let signal, let token, token != lastHandledToken else { return }
            playFly(for: signal.kind)
        }
        .onChange(of: toolbarFrames) { _, _ in
            guard let signal, signal.token != lastHandledToken, flyingKind == nil else { return }
            playFly(for: signal.kind)
        }
    }

    private func flyingBadge(for kind: ExportDeliverableKind) -> some View {
        Image(systemName: kind.icon)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(kind.tint)
                    .shadow(color: kind.tint.opacity(0.55), radius: 10, y: 3)
            )
    }

    private func playFly(for kind: ExportDeliverableKind) {
        guard
            let source = toolbarFrames[.export(kind)],
            let dest = toolbarFrames[.folder],
            source.width > 1, dest.width > 1
        else { return }

        lastHandledToken = signal?.token
        flyingKind = kind
        flySource = source
        flyDest = dest
        flyProgress = 0

        withAnimation(.easeInOut(duration: 0.5)) {
            flyProgress = 1
        }

        Task {
            try? await Task.sleep(nanoseconds: 520_000_000)
            await MainActor.run {
                flyingKind = nil
                flyProgress = 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    folderHighlighted = true
                }
            }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    folderHighlighted = false
                }
            }
        }
    }
}

extension View {
    func transcriptExportToolbarSlot(_ kind: ExportDeliverableKind) -> some View {
        background(TranscriptToolbarFrameReporter(slot: .export(kind)))
    }

    func transcriptExportFolderSlot() -> some View {
        background(TranscriptToolbarFrameReporter(slot: .folder))
    }
}
