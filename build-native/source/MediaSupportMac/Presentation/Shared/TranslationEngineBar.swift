import SwiftUI

/// Thanh chọn engine dịch — luôn hiện đầu tab Phụ đề (và Cài đặt).
struct TranslationEngineBar: View {
    @ObservedObject private var preferences = SubtitlePreferences.shared
    @AppStorage(GroqModelPreferences.textModelKey)
    private var groqTextModelRaw = GroqTextModel.quality.rawValue
    var showsSettingsAction = true

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            enginePicker
            if preferences.translationMode == .groq {
                groqModelPicker
            }
            Spacer(minLength: 12)
            if let warning = statusWarning {
                statusWarningView(warning)
            }
            if showsSettingsAction, needsSettingsAction {
                settingsButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTileSurface())
    }

    private var groqModelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mô hình")
                .font(AppFont.sectionHeader)
                .foregroundStyle(AppTheme.mutedText)
                .tracking(0.5)

            Picker("Mô hình Groq", selection: $groqTextModelRaw) {
                ForEach(GroqTextModel.allCases) { model in
                    Text(L10n.string(model.menuLabel)).tag(model.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            .help((GroqTextModel(rawValue: groqTextModelRaw) ?? .quality).detail)
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Engine dịch")
                .font(AppFont.sectionHeader)
                .foregroundStyle(AppTheme.mutedText)
                .tracking(0.5)

            Menu {
                ForEach(SubtitleTranslationMode.allCases) { mode in
                    Button {
                        preferences.translationMode = mode
                    } label: {
                        Label(L10n.string(mode.label), systemImage: mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: preferences.translationMode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                    Text(L10n.string(preferences.translationMode.label))
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppTheme.headlineText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppFieldSurface(radius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var statusWarning: (title: String, detail: String)? {
        guard !preferences.engineReady
            || preferences.engineStatusTitle == "Cần tải gói"
            || preferences.engineStatusTitle == "Không hỗ trợ"
            || preferences.engineStatusTitle == "Không khả dụng"
            || preferences.engineStatusTitle == "Thiếu API key"
        else { return nil }

        let detail = preferences.engineStatusDetail
        guard !detail.isEmpty || !preferences.engineReady else { return nil }
        return (preferences.engineStatusTitle, detail)
    }

    private func statusWarningView(_ warning: (title: String, detail: String)) -> some View {
        HStack(spacing: 10) {
            AppStatusDot(isActive: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(warning.title))
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.accentOrange)
                if !warning.detail.isEmpty {
                    Text(L10n.string(warning.detail))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                }
            }
        }
    }

    private var needsSettingsAction: Bool {
        preferences.translationMode != .appleLocal
            && !preferences.selectedProviderHasKey
    }

    private var settingsButton: some View {
        AppPillButton(
            title: "Cài đặt API",
            icon: "gearshape",
            tint: AppTheme.accentBlue,
            filled: false
        ) {
            AppCoordinator.shared.openSettings(
                tab: preferences.translationMode == .gemini ? .gemini : .groq
            )
        }
    }
}
