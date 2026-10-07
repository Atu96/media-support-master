import SwiftUI

struct SettingsAboutPanel: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") · \(info["CFBundleVersion"] as? String ?? "—")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Media Support Master").font(AppFont.sectionTitle)
                    Text(version).font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
                    Text(L10n.string("Chép lời, dịch, chỉnh phụ đề và lồng tiếng trong một Timeline trên Mac."))
                        .font(AppFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTileSurface())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("Thích ứng dụng này?")).font(AppFont.sectionTitle)
                    Text(L10n.string("Nếu app giúp bạn tiết kiệm thời gian, bạn có thể ủng hộ tác giả trên Ko-fi để tiếp tục cải thiện ứng dụng. Hoàn toàn tự nguyện — cảm ơn bạn đã sử dụng!"))
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.headlineText)
                        .fixedSize(horizontal: false, vertical: true)
                    AppSupportButton()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTileSurface())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
