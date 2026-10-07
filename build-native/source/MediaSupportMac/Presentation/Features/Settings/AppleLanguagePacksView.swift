import SwiftUI

struct AppleLanguagePacksView: View {
    @ObservedObject private var manager = AppleLanguagePackManager.shared
    var targetLang: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.format("Gói ngôn ngữ Apple → %@", targetLang))
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer()
                AppPillButton(
                    title: manager.isRefreshing ? "Đang quét…" : "Làm mới",
                    icon: "arrow.clockwise",
                    tint: AppTheme.accentBlue,
                    filled: false
                ) {
                    Task { await manager.refresh(targetLang: targetLang) }
                }
            }

            if !manager.downloadMessage.isEmpty {
                Text(manager.downloadMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            VStack(spacing: 0) {
                ForEach(manager.rows) { row in
                    packRow(row)
                    if row.id != manager.rows.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
            .background(AppFieldSurface(radius: 10))

            Text("Gói «Đã tải» dùng offline. «Chưa tải» — bấm Tải, macOS sẽ hiện hộp thoại hệ thống.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
        .onAppear {
            Task { await manager.refresh(targetLang: targetLang) }
        }
        .onChange(of: targetLang) { _, newValue in
            Task { await manager.refresh(targetLang: newValue) }
        }
    }

    private func packRow(_ row: AppleLanguagePackRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(row.name))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text("\(row.code) → \(row.targetLang)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            Spacer()
            statusBadge(row.status)
            if row.status == .needsDownload {
                AppPillButton(
                    title: "Tải",
                    icon: "arrow.down.circle",
                    tint: AppTheme.accentBlue,
                    filled: true
                ) {
                    manager.requestDownload(source: row.code, target: row.targetLang)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func statusBadge(_ status: AppleLanguagePackStatus) -> some View {
        HStack(spacing: 6) {
            AppStatusDot(isActive: status == .installed)
            Text(L10n.string(status.label))
                .font(AppFont.caption)
                .foregroundStyle(
                    status == .installed ? AppTheme.accentGreen :
                        status == .needsDownload ? AppTheme.accentOrange : AppTheme.mutedText
                )
        }
    }
}
