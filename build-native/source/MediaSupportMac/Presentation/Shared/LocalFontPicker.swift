import AppKit
import SwiftUI

@MainActor
final class LocalFontPickerDelegate: NSObject {
    var onChange: ((String) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let sender, let font = sender.selectedFont else { return }
        onChange?(font.fontName)
    }
}

struct LocalFontPickerButton: View {
    @Binding var fontName: String
    @State private var delegate = LocalFontPickerDelegate()

    var body: some View {
        Button {
            openPanel()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(.system(size: 11, weight: .semibold))
                Text(fontName)
                    .font(AppFont.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .foregroundStyle(AppTheme.headlineText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AppTheme.rowHeight)
            .background(AppFieldSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPlainButtonStyle())
        .onAppear {
            NSFontManager.shared.target = delegate
            delegate.onChange = { fontName = $0 }
        }
    }

    private func openPanel() {
        let panel = NSFontPanel.shared
        // Bấm lại khi đang mở → đóng.
        if panel.isVisible {
            SystemPanelAnchor.dismissFontPanel()
            return
        }

        SystemPanelAnchor.dismissColorPanel()

        let size: CGFloat = 12
        let font = NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        let manager = NSFontManager.shared

        manager.target = delegate
        panel.setPanelFont(font, isMultiple: false)
        manager.setSelectedFont(font, isMultiple: false)
        panel.isRestorable = false
        panel.hidesOnDeactivate = false

        manager.orderFrontFontPanel(delegate)
        SystemPanelAnchor.presentBesideBurnPanel(panel)
    }
}