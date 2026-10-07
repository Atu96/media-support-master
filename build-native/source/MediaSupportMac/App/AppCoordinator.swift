import AppKit

/// Điều phối app — navigation, engine status, mở cửa sổ phụ.
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var selectedSection: AppSection
    @Published var showSettingsSheet = false
    @Published private(set) var engineStatus: EngineStatus = AppPaths.engineStatus()

    let engine: MediaEngineServing = MediaEngineService.shared
    let preview: MediaPreviewServing = AVPreviewService.shared
    /// Sống suốt phiên — lazy để tránh vòng AppCoordinator ↔ SubtitleViewModel lúc launch.
    lazy var subtitleViewModel: SubtitleViewModel = SubtitleViewModel(coordinator: self)

    func selectSection(_ section: AppSection) {
        selectedSection = section
        persistSelectedSection(section)
        UserDefaults.standard.set(section.subtitleModuleTab.rawValue, forKey: "msm.subtitleSelectedTab")
        subtitleViewModel.syncPreviewForSubtitleTab(section.subtitleModuleTab)
    }

    private init() {
        AppPaths.ensureRuntimeDirs()
        selectedSection = Self.restoredSection()
    }

    func bootstrap() {
        SubtitleWorkspaceStorage.applyLaunchLayoutDefaults()
        SubtitleWorkspaceStorage.migrateLegacyChessboardLayoutIfNeeded()
        // Seed layout panel font/màu nếu chưa có — không ghi đè bản user đã căn.
        SystemPanelLayoutStore.applyReferencePreset(force: false)
        ProjectBackupStore.applyRetentionPolicy()
        refreshEngineStatus()
    }

    func refreshEngineStatus() {
        engineStatus = engine.refreshStatus()
    }

    func openMainWindow(section: AppSection? = nil) {
        if let section { selectSection(section) }
        MainWindowController.shared.show()
    }

    func presentSettings(tab: SettingsModuleTab? = nil) {
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: "msm.settingsSelectedTab")
        }
        showSettingsSheet = true
    }

    func openSettings(tab: SettingsModuleTab? = nil) {
        openMainWindow()
        presentSettings(tab: tab)
    }

    func openPreviewWindow(url: URL? = nil) {
        if let url { preview.load(url: url) }
        PreviewWindowController.shared.show()
    }

    func runCheckEngines() {
        Task {
            await engine.runCheckEngines()
            refreshEngineStatus()
        }
    }

    func shutdownForQuit() {
        MainWindowController.shared.close()
        PreviewWindowController.shared.close()
        engine.runner.shutdownForQuit()
        SystemResourceMonitor.shared.shutdownForQuit()
        preview.clear()
    }

    private static func restoredSection() -> AppSection {
        if let raw = UserDefaults.standard.string(forKey: "msm.selectedSection"),
           let section = AppSection(rawValue: raw) {
            return section
        }
        let tabRaw = UserDefaults.standard.string(forKey: "msm.subtitleSelectedTab") ?? ""
        if tabRaw == SubtitleModuleTab.script.rawValue {
            return .subtitleScript
        }
        return .subtitleCreate
    }

    private func persistSelectedSection(_ section: AppSection) {
        UserDefaults.standard.set(section.rawValue, forKey: "msm.selectedSection")
    }
}
