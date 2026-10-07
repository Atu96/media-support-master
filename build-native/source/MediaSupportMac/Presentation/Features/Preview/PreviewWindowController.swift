import AppKit
import SwiftUI

/// Cửa sổ preview tách riêng — mở từ khu vực phụ đề.
@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: DetachedPreviewView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Media Preview"
        window.setContentSize(NSSize(width: 900, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = true
        AppAppearance.apply(to: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// Nội dung cửa sổ preview tách — chỉ player, không sidebar.
private struct DetachedPreviewView: View {
    @ObservedObject private var preview = AVPreviewService.shared
    @StateObject private var viewModel = PreviewViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if preview.isLoaded {
                AVPlayerContainerView(player: preview.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Chưa có video — chọn từ tab Preview hoặc module khác")
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppWindowBackground())
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.pickAndLoad()
                } label: {
                    Label("Mở file", systemImage: "folder")
                }
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Label(
                        L10n.string(preview.isPlaying ? "Tạm dừng" : "Phát"),
                        systemImage: preview.isPlaying ? "pause" : "play"
                    )
                }
                .disabled(!preview.isLoaded)
            }
        }
    }
}
