import AppKit
import SwiftUI

/// App dùng trackpad/chuột để cuộn; ẩn toàn bộ thanh NSScroller để glass UI sạch.
private enum AppScrollbarVisibility {
    static func scheduleHideAll() {
        for delay in [0.0, 0.18, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows {
                    hide(in: window.contentView)
                }
            }
        }
    }

    private static func hide(in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView {
            scroll.scrollerStyle = .overlay
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.verticalScroller?.isHidden = true
            scroll.horizontalScroller?.isHidden = true
        }
        for subview in view.subviews { hide(in: subview) }
    }
}

private enum MainWindowJobAlert: Identifiable {
    case cloud(CloudAIErrorAlert)
    case log(EngineLogErrorAlert)

    var id: UUID {
        switch self {
        case let .cloud(alert): alert.id
        case let .log(alert): alert.id
        }
    }
}

struct MainWindowView: View {
    @ObservedObject private var coordinator = AppCoordinator.shared
    @AppStorage(AppAppearance.storageKey) private var colorThemeRaw = AppColorTheme.system.rawValue

    private var selectedColorTheme: AppColorTheme {
        AppColorTheme(rawValue: colorThemeRaw) ?? .system
    }

    private var jobAlert: Binding<MainWindowJobAlert?> {
        Binding(
            get: {
                if let cloud = coordinator.subtitleViewModel.cloudAlert {
                    return .cloud(cloud)
                }
                if let log = coordinator.subtitleViewModel.runner.lastLogErrorAlert {
                    return .log(log)
                }
                return nil
            },
            set: { alert in
                guard alert == nil else { return }
                coordinator.subtitleViewModel.cloudAlert = nil
                coordinator.subtitleViewModel.runner.dismissLastLogErrorAlert()
            }
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppShellGradient()

            VStack(spacing: 0) {
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !usesWideModuleLayout {
                    EngineResourceBar(placement: .window)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .preferredColorScheme(selectedColorTheme.colorScheme)
        .background {
            TranslationPackDownloadView()
        }
        .sheet(isPresented: $coordinator.showSettingsSheet) {
            SettingsModuleView()
        }
        .alert(item: jobAlert) { jobAlert in
            switch jobAlert {
            case let .cloud(alert) where alert.settingsTab != nil || alert.offersOfflineWhisper:
                Alert(
                    title: Text(L10n.string(alert.title)),
                    message: Text(L10n.string(alert.message)),
                    primaryButton: .default(Text(
                        alert.offersOfflineWhisper ? "Dùng Whisper Offline" : "Mở Cài đặt"
                    )) {
                        coordinator.subtitleViewModel.handleCloudAlertAction(alert)
                    },
                    secondaryButton: .cancel(Text("Đóng"))
                )
            case let .cloud(alert):
                Alert(
                    title: Text(L10n.string(alert.title)),
                    message: Text(L10n.string(alert.message)),
                    dismissButton: .default(Text("Đã hiểu"))
                )
            case let .log(alert):
                Alert(
                    title: Text("Không thể hoàn tất tác vụ"),
                    message: Text(L10n.format("%@\n\nChi tiết đầy đủ vẫn có trong Nhật ký.", alert.message)),
                    dismissButton: .default(Text("Đã hiểu"))
                )
            }
        }
        .onAppear {
            coordinator.refreshEngineStatus()
            MainWindowController.shared.applyWindowLayout(
                for: coordinator.selectedSection,
                animated: false
            )
            coordinator.subtitleViewModel.restoreLastSessionIfNeeded()
            coordinator.subtitleViewModel.syncPreviewForSubtitleTab(
                coordinator.selectedSection.subtitleModuleTab
            )
            AppScrollbarVisibility.scheduleHideAll()
        }
        .onChange(of: coordinator.selectedSection) { _, section in
            MainWindowController.shared.applyWindowLayout(for: section)
            AppScrollbarVisibility.scheduleHideAll()
        }
        .onChange(of: colorThemeRaw) { _, _ in
            AppAppearance.refreshAllWindows()
        }
        .onChange(of: coordinator.showSettingsSheet) { _, _ in AppScrollbarVisibility.scheduleHideAll() }
        .onChange(of: coordinator.subtitleViewModel.requestModuleTab) { _, tab in
            guard let tab else { return }
            switch tab {
            case .create:
                coordinator.selectSection(.subtitleCreate)
            case .script:
                coordinator.selectSection(.subtitleScript)
            }
            coordinator.subtitleViewModel.requestModuleTab = nil
        }
    }

    private var usesWideModuleLayout: Bool {
        true
    }

    private var detailPane: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellGradient())
    }

    @ViewBuilder
    private var moduleContent: some View {
        SubtitleTimelineWorkspace(viewModel: coordinator.subtitleViewModel)
    }
}
