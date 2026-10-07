import AppKit
import SwiftUI

/// Một phiên duy nhất — tránh hai nút màu dùng chung NSColorPanel mà cập nhật nhầm binding.
@MainActor
final class LocalColorPanelSession {
    static let shared = LocalColorPanelSession()

    private var observer: NSObjectProtocol?
    private var onChange: ((String) -> Void)?

    private init() {}

    func open(hex: String, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        // Bấm lại khi đang mở → đóng.
        if panel.isVisible {
            close()
            return
        }

        SystemPanelAnchor.dismissFontPanel()
        self.onChange = onChange

        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }

        panel.color = NSColor(SubtitleBurnStyle.color(fromHex: hex))
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.mode = .wheel
        panel.isRestorable = false
        panel.hidesOnDeactivate = false

        observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let rgb = NSColorPanel.shared.color.usingColorSpace(.sRGB) else { return }
                self.onChange?(SubtitleBurnStyle.hex(from: Color(nsColor: rgb)))
            }
        }

        SystemPanelAnchor.presentBesideBurnPanel(panel)
    }

    func close() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        onChange = nil
        NSColorPanel.shared.orderOut(nil)
    }
}

struct LocalColorPickerButton: View {
    @Binding var hex: String

    var body: some View {
        Button {
            LocalColorPanelSession.shared.open(hex: hex) { hex = $0 }
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SubtitleBurnStyle.color(fromHex: hex))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                )
                .frame(width: 44, height: 28)
        }
        .buttonStyle(AppPlainButtonStyle())
        .help("Chọn màu")
    }
}
