import AppKit
import SwiftUI

struct SettingsModuleView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("msm.settingsSelectedTab") private var selectedTabRaw = SettingsModuleTab.translate.rawValue
    @AppStorage(AppAppearance.storageKey) private var colorThemeRaw = AppColorTheme.system.rawValue

    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var subtitleVM = AppCoordinator.shared.subtitleViewModel
    @ObservedObject private var preferences = SubtitlePreferences.shared
    @ObservedObject private var backupPrefs = BackupPreferences.shared

    @State private var backupMessage = ""
    @State private var backupSizeLabel = "—"
    @State private var backupProjectCount = 0
    @State private var showPurgeAllConfirm = false
    @State private var showTechnicalDetails = false
    @State private var selectedAppLanguage = AppLanguagePreference.selected
    @State private var showLanguageRestart = false

    private var selectedTab: SettingsModuleTab {
        SettingsModuleTab(rawValue: selectedTabRaw) ?? .translate
    }

    private var sidebarGroups: [(title: String, tabs: [SettingsModuleTab])] {
        [
            ("TRÍ TUỆ NHÂN TẠO", [.translate, .groq, .gemini]),
            ("GIỌNG NÓI", [.dubbing]),
            ("TRÊN MÁY", [.offlineWhisper, .tools]),
            ("ỨNG DỤNG", [.appearance, .backup, .system, .about]),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(AppTheme.chromeRule)
                .frame(width: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                contentHeader

                Rectangle()
                    .fill(AppTheme.chromeRule)
                    .frame(height: 0.5)

                Group {
                    switch selectedTab {
                    case .translate:
                        translateTab
                    case .gemini:
                        SettingsGeminiKeyPanel()
                    case .groq:
                        SettingsGroqKeyPanel()
                    case .offlineWhisper:
                        SettingsOfflineWhisperPanel()
                    case .tools:
                        SettingsToolsPanel()
                    case .dubbing:
                        SettingsDubbingPanel()
                    case .appearance:
                        appearanceTab
                    case .backup:
                        backupTab
                    case .system:
                        systemTab
                    case .about:
                        SettingsAboutPanel()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(
            width: AppTheme.settingsSheetSize.width,
            height: AppTheme.settingsSheetSize.height
        )
        .fixedSize()
        .background(AppShellGradient())
        .preferredColorScheme(selectedColorTheme.colorScheme)
        .onChange(of: colorThemeRaw) { _, _ in
            AppAppearance.refreshAllWindows()
        }
        .alert("Mở lại ứng dụng để đổi ngôn ngữ?", isPresented: $showLanguageRestart) {
            Button("Để sau", role: .cancel) {}
            Button("Mở lại ngay") {
                AppLanguagePreference.relaunchCurrentBundle()
            }
        } message: {
            Text("Ngôn ngữ mới sẽ áp dụng cho toàn bộ menu và giao diện sau khi ứng dụng mở lại.")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                        .fill(AppTheme.controlFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                                .strokeBorder(AppTheme.tileStroke, lineWidth: AppTheme.hairlineWidth)
                        }
                        .frame(width: 34, height: 34)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cài đặt")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppTheme.headlineText)
                    Text("Media Support Master")
                        .font(AppFont.editorLabel)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(sidebarGroups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string(group.title))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.45)
                            .foregroundStyle(AppTheme.mutedText.opacity(0.78))
                            .padding(.horizontal, 10)

                        ForEach(group.tabs) { tab in
                            sidebarButton(tab)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            Text(appVersionLabel)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(AppTheme.mutedText.opacity(0.8))
                .padding(16)
        }
        .frame(width: 204)
        .background(AppTheme.tileFill.opacity(0.46))
    }

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(selectedTab.title))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.headlineText)
                Text(L10n.string(selectedTab.subtitle))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(TimelineToolbarButtonStyle())
            .help("Đóng")
            .accessibilityLabel("Đóng Cài đặt")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func sidebarButton(_ tab: SettingsModuleTab) -> some View {
        let selected = selectedTab == tab
        let needsAttention = (tab == .gemini
            && preferences.translationMode == .gemini
            && (!GeminiCredentialStore.hasKey || preferences.geminiQuotaExceeded))
            || (tab == .groq
                && preferences.translationMode == .groq
                && !GroqCredentialStore.hasKey)

        return Button {
            selectedTabRaw = tab.rawValue
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(L10n.string(tab.title))
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if needsAttention {
                    Circle()
                        .fill(AppTheme.accentOrange)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(selected ? AppTheme.accentBlue : AppTheme.headlineText.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selected ? AppTheme.controlHover : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(selected ? AppTheme.accentBlue : Color.clear)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPlainButtonStyle())
        .accessibilityLabel(L10n.string(tab.title))
        .accessibilityValue(L10n.string(selected ? "Đang chọn" : "Chưa chọn"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Dịch

    private var translateTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsTile(title: "Dịch và tóm tắt") {
                    Picker("Nhà cung cấp", selection: $preferences.translationMode) {
                        ForEach(SubtitleTranslationMode.allCases) { mode in
                            Label(L10n.string(mode.label), systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    engineStatusRow

                    Text(L10n.string(providerPrivacyNote))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }

                if preferences.translationMode == .appleLocal {
                    settingsTile(title: "Gói ngôn ngữ Apple") {
                        AppleLanguagePacksView(targetLang: subtitleVM.targetLang)
                    }
                }

                settingsTile(title: "Ngôn ngữ mặc định") {
                    SubtitleTargetLanguagePicker(
                        selection: $subtitleVM.targetLang,
                        label: "Ngôn ngữ đích"
                    )
                    .onChange(of: subtitleVM.targetLang) { _, _ in
                        subtitleVM.syncPreferencesContext()
                    }

                    settingsLabeledField("Nguồn", value: $subtitleVM.sourceLang, placeholder: "auto", width: 120)
                        .onChange(of: subtitleVM.sourceLang) { _, _ in
                            subtitleVM.syncPreferencesContext()
                        }

                    if subtitleVM.mediaURL != nil {
                        AppPillButton(
                            title: "Nhận diện từ media",
                            icon: "ear",
                            tint: AppTheme.accentBlue,
                            filled: false,
                            disabled: !subtitleVM.canDetectFromMedia
                        ) {
                            subtitleVM.detectLanguageFromMedia()
                        }
                    }
                }

                settingsTile(title: "Ngôn ngữ tóm tắt") {
                    Picker("Ngôn ngữ", selection: $preferences.summaryOutputLang) {
                        ForEach(SubtitlePreferences.summaryLanguageOptions) { option in
                            Text(L10n.string(option.label)).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240, alignment: .leading)

                    Text("Bản tóm tắt sử dụng nhà cung cấp AI đã chọn.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var providerPrivacyNote: String {
        if preferences.translationMode == .appleLocal {
            return "Apple Local xử lý trên máy, không gửi nội dung phụ đề đến dịch vụ bên ngoài."
        }
        return "Nội dung phụ đề được gửi đến nhà cung cấp bạn chọn. Khóa API được lưu an toàn trong Keychain."
    }

    private var engineStatusRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(preferences.engineStatusTitle))
                        .font(AppFont.label)
                        .foregroundStyle(preferences.engineReady ? AppTheme.headlineText : AppTheme.accentOrange)
                    if !preferences.engineStatusDetail.isEmpty {
                        Text(L10n.string(preferences.engineStatusDetail))
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
                Spacer(minLength: 0)
            }

            if needsProviderSettingsAction {
                AppPillButton(
                    title: isGeminiQuotaIssue ? "Đổi API key" : "Nhập API key",
                    icon: "key.fill",
                    tint: AppTheme.accentBlue,
                    filled: isGeminiQuotaIssue,
                    action: {
                        selectedTabRaw = preferences.translationMode == .gemini
                            ? SettingsModuleTab.gemini.rawValue
                            : SettingsModuleTab.groq.rawValue
                    }
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.fieldRadius, style: .continuous)
                .fill(isGeminiQuotaIssue ? AppTheme.accentOrange.opacity(0.08) : AppTheme.inputFill)
        )
    }

    private var statusDotColor: Color {
        if isGeminiQuotaIssue { return AppTheme.accentOrange }
        return preferences.engineReady ? AppTheme.accentGreen : AppTheme.accentOrange
    }

    private var isGeminiQuotaIssue: Bool {
        preferences.translationMode == .gemini && preferences.geminiQuotaExceeded
    }

    private var needsProviderSettingsAction: Bool {
        isGeminiQuotaIssue || !preferences.selectedProviderHasKey
    }

    // MARK: - Backup

    private var backupTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsTile(title: "Bản sao dự án") {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accentBlue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.format("%d dự án · %@", backupProjectCount, backupSizeLabel))
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text(backupPrefs.backupRootURL.path)
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        AppPillButton(title: "Đổi vị trí", icon: "folder", tint: AppTheme.accentBlue, filled: false) {
                            pickBackupFolder()
                        }
                        AppPillButton(title: "Mở thư mục", icon: "arrow.up.forward.app", tint: AppTheme.accentBlue, filled: false) {
                            openBackupFolder()
                        }
                    }
                }

                settingsTile(title: "Tệp xuất") {
                    Toggle("Lưu SRT cạnh tệp media", isOn: $backupPrefs.mirrorSRTBesideMedia)
                    Toggle("Lưu video đã gắn phụ đề cạnh tệp gốc", isOn: $backupPrefs.mirrorSubbedBesideMedia)
                    Toggle("Xóa bản sao sau khi xuất video", isOn: $backupPrefs.autoPurgeBackupOnBurn)
                }

                settingsTile(title: "Dọn dẹp tự động") {
                    HStack(spacing: 12) {
                        Text("Thời gian lưu")
                            .font(AppFont.label)
                            .foregroundStyle(AppTheme.headlineText)

                        Picker("Thời gian lưu", selection: $backupPrefs.retentionDays) {
                            Text("Không tự xóa").tag(0)
                            Text("7 ngày").tag(7)
                            Text("14 ngày").tag(14)
                            Text("30 ngày").tag(30)
                            Text("90 ngày").tag(90)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200, alignment: .leading)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        AppPillButton(title: "Dọn bản sao cũ", icon: "clock.arrow.circlepath", tint: AppTheme.accentOrange, filled: false) {
                        purgeStaleBackups()
                        }
                        AppPillButton(title: "Xóa mọi bản sao", icon: "trash", tint: AppTheme.accentRed, filled: false) {
                            showPurgeAllConfirm = true
                        }
                    }
                }

                if !backupMessage.isEmpty {
                    Text(L10n.string(backupMessage))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.bottom, 8)
            .onAppear { refreshBackupStats() }
            .onChange(of: backupPrefs.backupRootURL) { _, _ in refreshBackupStats() }
            .onChange(of: backupPrefs.retentionDays) { _, _ in
                ProjectBackupStore.applyRetentionPolicy()
                refreshBackupStats()
            }
            .alert("Xóa mọi bản sao dự án?", isPresented: $showPurgeAllConfirm) {
                Button("Xóa", role: .destructive) { purgeAllBackups() }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Tệp media gốc và các tệp đã xuất sẽ không bị xóa.")
            }
        }
    }

    // MARK: - Hệ thống

    private var selectedColorTheme: AppColorTheme {
        AppColorTheme(rawValue: colorThemeRaw) ?? .system
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsTile(title: "Ngôn ngữ ứng dụng") {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppTheme.accentBlue)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ngôn ngữ hiển thị")
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text("Theo hệ thống dùng ngôn ngữ ưu tiên của macOS.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }

                        Spacer(minLength: 12)

                        Picker("Ngôn ngữ ứng dụng", selection: $selectedAppLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 190)
                        .onChange(of: selectedAppLanguage) { _, language in
                            guard language != AppLanguagePreference.selected else { return }
                            AppLanguagePreference.apply(language)
                            showLanguageRestart = true
                        }
                    }
                }

                settingsTile(title: "Chế độ màu") {
                    Text("Chọn giao diện phù hợp không gian làm việc. “Theo hệ thống” tự đổi cùng macOS.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)

                    HStack(spacing: 10) {
                        ForEach(AppColorTheme.allCases) { theme in
                            appearanceChoice(theme)
                        }
                    }
                }

                settingsTile(title: "Độ tương phản") {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.righthalf.filled")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AppTheme.accentBlue)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tương phản tối ưu tự động")
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text("Chữ, viền, vùng nhập và trạng thái nút tự dùng bảng màu riêng cho Sáng và Tối.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func appearanceChoice(_ theme: AppColorTheme) -> some View {
        let selected = selectedColorTheme == theme
        return Button {
            colorThemeRaw = theme.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: theme.icon)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppTheme.accentBlue : AppTheme.mutedText)
                }
                Text(L10n.string(theme.title))
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(theme == .dark ? Color(red: 0.06, green: 0.09, blue: 0.14) : Color(red: 0.91, green: 0.95, blue: 0.99))
                    RoundedRectangle(cornerRadius: 4).fill(theme == .light ? Color.white : Color(red: 0.12, green: 0.18, blue: 0.28))
                    RoundedRectangle(cornerRadius: 4).fill(AppTheme.accentBlue)
                }
                .frame(height: 24)
            }
            .foregroundStyle(selected ? AppTheme.accentBlue : AppTheme.headlineText)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(selected ? AppTheme.accentBlue.opacity(0.10) : AppTheme.inputFill)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? AppTheme.focusRing : AppTheme.tileStroke, lineWidth: selected ? 1.4 : 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityLabel(L10n.format("Giao diện %@", L10n.string(theme.title)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var systemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsTile(title: "Tình trạng ứng dụng") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(systemStatusColor.opacity(0.14))
                                .frame(width: 42, height: 42)
                            Image(systemName: coordinator.engineStatus.issues.isEmpty
                                ? "checkmark.shield.fill"
                                : "exclamationmark.triangle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(systemStatusColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(coordinator.engineStatus.issues.isEmpty
                                ? "Các thành phần đã sẵn sàng"
                                : "Cần kiểm tra một số thành phần")
                                .font(AppFont.label)
                                .foregroundStyle(AppTheme.headlineText)
                            Text("Kiểm tra công cụ xử lý media và kết nối cần thiết.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }

                    AppPillButton(
                        title: "Kiểm tra lại",
                        icon: "arrow.clockwise",
                        tint: AppTheme.accentBlue,
                        filled: true,
                        action: { coordinator.runCheckEngines() }
                    )
                }

                if !coordinator.engineStatus.issues.isEmpty {
                    settingsTile(title: "Cần chú ý") {
                        Label(
                            "\(coordinator.engineStatus.issues.count) thành phần hỗ trợ chưa sẵn sàng",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.accentOrange)

                        Text("Mở Chi tiết chẩn đoán khi cần gửi thông tin cho bộ phận hỗ trợ.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                settingsTile(title: "Hỗ trợ kỹ thuật") {
                    DisclosureGroup("Chi tiết chẩn đoán", isExpanded: $showTechnicalDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsPathRow("Thành phần bổ trợ", AppPaths.toolsRoot.path)
                            settingsPathRow("Tác vụ hệ thống", AppPaths.scriptsDir.path)
                            settingsPathRow("Bản sao dự án", AppPaths.backupRoot.path)
                            if let ffmpeg = AppPaths.resolveFFmpeg() {
                                settingsPathRow("Bộ xử lý media", ffmpeg)
                            }

                            ForEach(coordinator.engineStatus.issues, id: \.self) { issue in
                                Text(L10n.string(issue))
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppTheme.accentOrange)
                            }

                            if let engine = coordinator.engine as? MediaEngineService {
                                LogConsoleView(runner: engine.runner, compactLines: 6, startsExpanded: false)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
        }
    }

    private var systemStatusColor: Color {
        coordinator.engineStatus.issues.isEmpty ? AppTheme.accentGreen : AppTheme.accentOrange
    }

    // MARK: - Shared chrome

    private func settingsTile<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func settingsPathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.string(label))
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
            Text(path)
                .font(AppFont.mono)
                .foregroundStyle(AppTheme.headlineText)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func settingsLabeledField(
        _ label: String,
        value: Binding<String>,
        placeholder: String,
        width: CGFloat
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.string(label))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 100, alignment: .leading)
            TextField(placeholder, text: value)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: width)
                .background(AppFieldSurface(radius: 8))
        }
    }

    // MARK: - Actions

    private func refreshBackupStats() {
        backupProjectCount = ProjectBackupStore.listIndexEntries().count
        backupSizeLabel = formatBytes(ProjectBackupStore.estimatedTotalSize())
    }

    private func pickBackupFolder() {
        FilePickerHelper.pickDirectory { url in
            backupPrefs.backupRootURL = url
            backupMessage = "Đã đổi thư mục."
            refreshBackupStats()
        }
    }

    private func openBackupFolder() {
        ProjectBackupStore.ensureLayout()
        NSWorkspace.shared.open(backupPrefs.backupRootURL)
    }

    private func purgeStaleBackups() {
        let days = backupPrefs.retentionDays
        guard days > 0 else {
            backupMessage = "Hãy chọn thời gian lưu trước khi dọn."
            return
        }
        ProjectBackupStore.purgeStale(olderThan: days)
        backupMessage = L10n.format("Đã xóa các bản sao cũ hơn %d ngày.", days)
        refreshBackupStats()
    }

    private func purgeAllBackups() {
        ProjectBackupStore.purgeAll()
        backupMessage = "Đã xóa mọi bản sao dự án."
        refreshBackupStats()
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return L10n.format("Phiên bản %@", version)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }
}
