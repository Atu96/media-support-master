import SwiftUI

/// Split control: «Dịch» (chạy ngay) + chevron (chỉ đổi ngôn ngữ đích) — cùng style AppPillButton.
struct SubtitleTranslateMenuButton: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var preferences = SubtitlePreferences.shared

    private var isRunning: Bool { viewModel.isRunningTranslate }

    private var isDisabled: Bool {
        viewModel.segments.isEmpty
            || !viewModel.whisperComplete
            || viewModel.srtURL == nil
            || !viewModel.canRunTranslate
    }

    private var targetLangShort: String {
        SubtitleLanguageCatalog.shortToken(for: viewModel.targetLang)
    }

    private var primaryTitle: String {
        if isRunning {
            if viewModel.translateProgressTotal > 0 {
                let percent = L10n.format("Dịch %d%%", viewModel.translateProgressPercent)
                let stage = viewModel.translateProgressStage
                return stage.isEmpty ? percent : "\(percent) · \(L10n.string(stage))"
            }
            return L10n.string("Đang dịch…")
        }
        return L10n.format("Dịch (%@)", targetLangShort)
    }

    private var targetLangLabel: String {
        SubtitleLanguageCatalog.option(for: viewModel.targetLang)?.localizedName
            ?? viewModel.targetLang.uppercased()
    }

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.needsCloudKeySettings {
                cloudSettingsChip
            }

            translateControl
        }
        .fixedSize()
    }

    private var translateControl: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.runTranslate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRunning ? "character.book.closed.fill" : "character.book.closed")
                        .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                    Text(primaryTitle)
                        .font(AppFont.editorLabel)
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.headlineText)
                .padding(.leading, 9)
                .padding(.trailing, 8)
                .frame(height: AppTheme.compactControlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPressableButtonStyle())
            .disabled(isDisabled || isRunning)
            .help(primaryHelp)
            .accessibilityLabel(primaryTitle)
            .accessibilityHint(primaryHelp)

            splitDivider

            Menu {
                if let reason = viewModel.translateDisabledReason, !viewModel.canRunTranslate {
                    Text(L10n.string(reason))
                    Divider()
                }

                let recent = SubtitleLanguageCatalog.recentCodes()
                if !recent.isEmpty {
                    Section("Gần đây") {
                        ForEach(recent, id: \.self) { code in
                            languageItem(code)
                        }
                    }
                }

                Section("Ngôn ngữ đích") {
                    ForEach(SubtitleLanguageCatalog.targetLanguages) { lang in
                        languageItem(lang.code)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.headlineText)
                    .frame(width: 28, height: AppTheme.compactControlHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(isDisabled)
            .help(menuHelp)
            .accessibilityLabel(L10n.string("Chọn ngôn ngữ đích"))
            .accessibilityHint(menuHelp)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                .fill(AppTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                .strokeBorder(AppTheme.tileStroke.opacity(0.62), lineWidth: AppTheme.hairlineWidth)
        )
        .opacity(isDisabled ? 0.38 : 1)
    }

    private var cloudSettingsChip: some View {
        Button {
            viewModel.openCloudKeySettings()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isQuotaIssue ? "exclamationmark.triangle.fill" : "key.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.string(isQuotaIssue ? "Hết quota" : "Thiếu key"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accentOrange)
                .padding(.horizontal, 9)
                .frame(height: AppTheme.compactControlHeight)
                .background(
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .fill(AppTheme.accentOrange.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                            .strokeBorder(AppTheme.accentOrange.opacity(0.35), lineWidth: AppTheme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(AppPlainButtonStyle())
        .help(isQuotaIssue
            ? L10n.string("Gemini hết usage — bấm để đổi key")
            : L10n.format("Chưa có %@ key — bấm để nhập", L10n.string(preferences.translationMode.label)))
        .accessibilityLabel(L10n.string(isQuotaIssue ? "Gemini hết quota" : "Thiếu khóa API"))
    }

    private var isQuotaIssue: Bool {
        preferences.translationMode == .gemini && preferences.geminiQuotaExceeded
    }

    private var splitDivider: some View {
        Rectangle()
            .fill(AppTheme.divider.opacity(0.85))
            .frame(width: AppTheme.hairlineWidth, height: 18)
    }

    @ViewBuilder
    private func languageItem(_ code: String) -> some View {
        let selected = AppleSRTTranslator.normalizeLangCode(viewModel.targetLang) == code
        Button {
            viewModel.selectTargetLanguage(code)
        } label: {
            HStack {
                Text(SubtitleLanguageCatalog.displayTitle(for: code))
                if selected {
                    Spacer(minLength: 12)
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var primaryHelp: String {
        if isDisabled {
            if viewModel.segments.isEmpty || !viewModel.whisperComplete {
                return L10n.string("Chép lời xong mới dịch được")
            }
            return L10n.string(viewModel.translateDisabledReason ?? "Chưa sẵn sàng dịch")
        }
        return L10n.format("Dịch sang %@ — %@", targetLangLabel, L10n.string(preferences.translationMode.label))
    }

    private var menuHelp: String {
        L10n.string("Chọn ngôn ngữ đích — bấm «Dịch» để chạy")
    }
}

/// Picker ngôn ngữ dài — dùng trong Cài đặt (menu native hệ thống).
struct SubtitleTargetLanguagePicker: View {
    @Binding var selection: String
    var label: String
    var maxWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)

            Picker(label, selection: $selection) {
                let recent = SubtitleLanguageCatalog.recentCodes()
                if !recent.isEmpty {
                    Section(L10n.string("Gần đây")) {
                        ForEach(recent, id: \.self) { code in
                            Text(SubtitleLanguageCatalog.displayTitle(for: code))
                                .tag(AppleSRTTranslator.normalizeLangCode(code))
                        }
                    }
                }
                Section(L10n.string("Tất cả")) {
                    ForEach(SubtitleLanguageCatalog.targetLanguages) { lang in
                        Text(lang.displayTitle).tag(lang.code)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }
}
