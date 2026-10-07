import AppKit
import SwiftUI

struct SettingsOfflineWhisperPanel: View {
    @ObservedObject private var manager = OfflineWhisperModelManager.shared
    @AppStorage("msm.offlineWhisper.useForNextRun") private var useForNextRun = false
    @State private var showDeleteConfirm = false
    @State private var deleteMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsTile(title: "Model chép lời") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.string(statusTitle))
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text(L10n.string(statusDetail))
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }

                    if case .downloading = manager.status {
                        ProgressView(value: manager.progress)
                            .tint(AppTheme.accentBlue)
                        Text("\(byteLabel(manager.downloadedBytes)) / \(byteLabel(manager.totalBytes))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    } else if case .verifying = manager.status {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang kiểm tra checksum trước khi kích hoạt…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }

                    HStack(spacing: 10) {
                        actionButtons
                    }

                    if !deleteMessage.isEmpty {
                        Text(L10n.string(deleteMessage))
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                settingsTile(title: "Quyền riêng tư") {
                    Text("Khi dùng Whisper Offline, âm thanh được xử lý hoàn toàn trên máy Mac và không được gửi đến dịch vụ bên ngoài.")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.headlineText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Ứng dụng xác minh model trước khi sử dụng. Việc xóa model không ảnh hưởng đến phụ đề hoặc dự án hiện có.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsTile(title: "Dung lượng") {
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accentBlue)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Khoảng 1,62 GB")
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text("Model được lưu riêng trong dữ liệu ứng dụng.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }

                    AppPillButton(
                        title: "Mở vị trí lưu",
                        icon: "folder",
                        tint: AppTheme.accentBlue,
                        filled: false
                    ) {
                        try? FileManager.default.createDirectory(
                            at: OfflineWhisperModelManager.modelsDirectory,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(OfflineWhisperModelManager.modelsDirectory)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            manager.refreshStatus()
            if !OfflineWhisperModelManager.isModelReady,
               FileManager.default.fileExists(atPath:OfflineWhisperModelManager.modelURL.path)
                || FileManager.default.fileExists(atPath:AppPaths.whisperHome.appendingPathComponent(OfflineWhisperModelManager.modelFileName).path) {
                // A local verification/import only; never download on opening Settings.
                Task { _ = try? await OfflineWhisperModelManager.ensureAvailableModel() }
            }
        }
        .alert("Xóa model Whisper Offline?", isPresented: $showDeleteConfirm) {
            Button("Xóa model", role: .destructive) { deleteModel() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Giải phóng khoảng 1,62 GB. Phụ đề và dự án hiện có không bị ảnh hưởng.")
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch manager.status {
        case .notInstalled, .failed:
            AppPillButton(
                title: "Tải Whisper Turbo",
                icon: "arrow.down.circle.fill",
                tint: AppTheme.accentBlue,
                filled: true,
                action: manager.startDownload
            )
        case .downloading:
            AppPillButton(
                title: "Huỷ tải",
                icon: "xmark.circle",
                tint: AppTheme.accentOrange,
                filled: false,
                action: manager.cancelDownload
            )
        case .verifying:
            EmptyView()
        case .ready:
            AppPillButton(
                title: useForNextRun ? "Đã chọn cho lần tiếp theo" : "Dùng Offline cho lần tiếp theo",
                icon: useForNextRun ? "checkmark.circle.fill" : "play.circle",
                tint: AppTheme.accentBlue,
                filled: useForNextRun
            ) {
                useForNextRun.toggle()
            }
            AppPillButton(
                title: "Xóa model",
                icon: "trash",
                tint: AppTheme.accentRed,
                filled: false
            ) {
                showDeleteConfirm = true
            }
        }
    }

    private var statusTitle: String {
        switch manager.status {
        case .notInstalled: "Chưa tải model"
        case .downloading: "Đang tải Whisper Turbo"
        case .verifying: "Đang xác minh model"
        case .ready: "Whisper Offline sẵn sàng"
        case .failed: "Tải model chưa hoàn tất"
        }
    }

    private var statusDetail: String {
        switch manager.status {
        case .notInstalled:
            "Tải một lần để chép lời trên máy khi không có mạng hoặc khi dịch vụ cloud gián đoạn."
        case .downloading:
            "Có thể huỷ; file chưa hoàn tất sẽ không được dùng."
        case .verifying:
            "App đang kiểm tra dung lượng và checksum SHA-256."
        case .ready:
            "Sẵn sàng chép lời trên máy và làm phương án dự phòng cho dịch vụ cloud."
        case let .failed(message):
            message
        }
    }

    private var statusColor: Color {
        switch manager.status {
        case .ready: AppTheme.accentGreen
        case .downloading, .verifying: AppTheme.accentBlue
        case .failed: AppTheme.accentRed
        case .notInstalled: AppTheme.accentOrange
        }
    }

    private func deleteModel() {
        do {
            try manager.deleteModel()
            useForNextRun = false
            deleteMessage = L10n.string("Đã xóa model offline.")
        } catch {
            deleteMessage = L10n.format("Không xóa được model: %@", error.localizedDescription)
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func settingsTile<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string(title))
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}
