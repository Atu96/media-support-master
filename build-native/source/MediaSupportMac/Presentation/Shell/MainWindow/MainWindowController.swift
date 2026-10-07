import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var exportAccessory: NSTitlebarAccessoryViewController?

    private override init() {
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: MainWindowView())
        let window = NSWindow(contentViewController: hosting)
        // Tên app đã ở menu bar; titlebar giữ hành động chính của workspace.
        window.title = ""
        window.minSize = NSSize(width: 820, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Chỉ `WindowDragHandle` trên header được phép kéo cửa sổ. Nếu bật cờ
        // này, mọi vùng nền trống của timeline đều vô tình kéo app theo chuột.
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = true
        window.delegate = self
        installExportAccessory(on: window)
        AppAppearance.apply(to: window)
        fillVisibleScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }

    func applyWindowLayout(for section: AppSection, animated: Bool = true) {
        guard let window else { return }
        fillVisibleScreen(window, animated: animated)
    }

    func windowWillClose(_ notification: Notification) {
        exportAccessory = nil
        window = nil
    }

    private func installExportAccessory(on window: NSWindow) {
        let controller = NSTitlebarAccessoryViewController()
        controller.layoutAttribute = .left
        let hosting = NSHostingView(rootView: TitlebarExportSettingsView(
            viewModel: AppCoordinator.shared.subtitleViewModel
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 142, height: 28)
        controller.view = hosting
        window.addTitlebarAccessoryViewController(controller)
        exportAccessory = controller
    }

    private func fillVisibleScreen(_ window: NSWindow, animated: Bool = false) {
        let frame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window.setFrame(frame, display: true, animate: animated)
    }

    private func setCompactContentSize(
        _ window: NSWindow,
        width: CGFloat,
        height: CGFloat,
        animated: Bool
    ) {
        let screen = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height))
        frame.origin.x = screen.midX - frame.width * 0.5
        frame.origin.y = screen.midY - frame.height * 0.5

        if frame.width > screen.width {
            frame.size.width = screen.width
            frame.origin.x = screen.minX
        }
        if frame.height > screen.height {
            frame.size.height = screen.height
            frame.origin.y = screen.minY
        }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }

        window.setFrame(frame, display: true, animate: animated)
    }
}

private struct TitlebarExportSettingsView: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var dubbingSession = DubbingSessionModel.shared

    var body: some View {
        Menu {
            Button {
                viewModel.burnStyle.save()
                viewModel.burnSubtitlesIntoVideo()
            } label: {
                Label("Xuất video phụ đề", systemImage: "captions.bubble.fill")
            }
            .disabled(!viewModel.canBurnSubtitles || viewModel.isBurningSubtitles)

            if AppFeatureFlags.dubbingEnabled {
                Button {
                    presentDubbingExportPanel()
                } label: {
                    Label("Xuất video lồng tiếng", systemImage: "waveform.badge.mic")
                }
                .disabled(
                    viewModel.mediaURL == nil
                        || dubbingSession.effectiveRenderedCues.isEmpty
                        || dubbingSession.isExporting
                )
            }

            Divider()
            Picker("FPS XML", selection: $viewModel.burnStyle.fps) {
                ForEach(["24", "25", "30", "60"], id: \.self) { fps in
                    Text("\(fps) FPS").tag(fps)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isBurningSubtitles || dubbingSession.isExporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(L10n.string(viewModel.isBurningSubtitles || dubbingSession.isExporting ? "Đang xuất…" : "Cài đặt xuất"))
                    .font(AppFont.editorBodyStrong)
            }
            .foregroundStyle(AppTheme.headlineText)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .strokeBorder(AppTheme.tileStroke, lineWidth: AppTheme.hairlineWidth)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Cài đặt xuất")
        .accessibilityLabel("Cài đặt xuất")
        .padding(.horizontal, 4)
        .frame(height: 28)
    }

    private func presentDubbingExportPanel() {
        guard let mediaURL = viewModel.mediaURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = mediaURL.deletingPathExtension().lastPathComponent + "_dub.mov"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        dubbingSession.exportMix(mediaURL: mediaURL, outputURL: outputURL)
    }
}
