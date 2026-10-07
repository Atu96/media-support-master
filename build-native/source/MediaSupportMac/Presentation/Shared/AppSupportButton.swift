import AppKit
import SwiftUI

@MainActor
enum AppSupport {
    static func open() {
        guard !NSWorkspace.shared.open(AppSupportLink.url) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.string("Không thể mở trang ủng hộ")
        alert.informativeText = AppSupportLink.url.absoluteString
        alert.addButton(withTitle: L10n.string("Đóng"))
        alert.addButton(withTitle: L10n.string("Sao chép liên kết"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AppSupportLink.url.absoluteString, forType: .string)
        }
    }
}

struct AppSupportButton: View {
    var body: some View {
        Button(action: AppSupport.open) {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Text(L10n.string("Ủng hộ")).foregroundStyle(AppTheme.mutedText)
            }
            .font(AppFont.caption)
            .padding(.horizontal, 7)
            .frame(height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPlainButtonStyle())
        .help(L10n.string("Mở Ko-fi trong trình duyệt. Hoàn toàn tự nguyện."))
        .accessibilityLabel(L10n.string("Ủng hộ tác giả trên Ko-fi"))
    }
}
