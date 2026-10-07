import SwiftUI

struct SettingsDubbingPanel: View {
    @ObservedObject private var session = DubbingSessionModel.shared
    @StateObject private var voicePreview = DubbingVoicePreviewController()
    @State private var googleKeyDraft = ""
    @State private var elevenKeyDraft = ""
    @State private var maziaoKeyDraft = ""
    @State private var feedback = ""
    @State private var googleUsage = ProviderUsageStore.googleLocalUsage()
    @State private var elevenQuota = ProviderUsageStore.elevenLabsSnapshot()
    @State private var isRefreshingElevenQuota = false
    @State private var elevenQuotaError = ""
    @State private var maziaoAccount = ProviderUsageStore.maziaoSnapshot()
    @State private var isRefreshingMaziao = false
    @State private var maziaoError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                providerCard
                selectedProviderCard
                cacheCard
                privacyCard
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: session.speechProvider) {
            voicePreview.stop()
            googleUsage = ProviderUsageStore.googleLocalUsage()
            session.refreshCacheUsage()
            switch session.speechProvider {
            case .googleCloud where session.hasCredential(for: .googleCloud):
                await session.refreshGoogleVoiceCatalog()
            case .elevenLabs where session.hasCredential(for: .elevenLabs):
                await session.refreshElevenVoiceCatalog()
                await refreshElevenQuota()
            case .maziao where session.hasCredential(for: .maziao):
                await refreshMaziao()
            default:
                break
            }
        }
    }

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cache lồng tiếng")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppTheme.headlineText)
                    Text(L10n.format("%@ · %d tệp", session.cacheSizeLabel, session.cacheUsage.clipCount))
                        .font(AppFont.mono)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer(minLength: 0)
            }

            Text("Thường khoảng 6–12 MB/phút với CAF; cue đã gộp dùng M4A nhẹ hơn.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)

            HStack(spacing: 8) {
                AppPillButton(
                    title: "Làm mới dung lượng cache",
                    icon: "arrow.clockwise",
                    tint: AppTheme.accentBlue,
                    filled: false
                ) {
                    session.refreshCacheUsage()
                }
                AppPillButton(
                    title: "Xóa cache lồng tiếng",
                    icon: "trash",
                    tint: AppTheme.accentRed,
                    filled: false
                ) {
                    session.clearCache()
                }
            }
        }
        .padding(14)
        .background(AppTileSurface())
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nhà cung cấp giọng nói")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)

            Picker("Nhà cung cấp giọng nói", selection: $session.speechProvider) {
                ForEach(DubbingSpeechProvider.allCases) { provider in
                    Label(provider.label, systemImage: provider.icon).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)

            Text(L10n.string(session.speechProvider.detail))
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(14)
        .background(AppTileSurface())
    }

    @ViewBuilder
    private var selectedProviderCard: some View {
        switch session.speechProvider {
        case .googleCloud:
            googleCard
        case .maziao:
            maziaoCard
        case .elevenLabs:
            elevenCard
        case .appleOffline:
            appleCard
        }
    }

    private var maziaoCard: some View {
        DubbingSettingsCard(title: "Maziao", icon: "waveform.circle.fill", connected: session.hasCredential(for: .maziao), feedback: feedback) {
            DubbingSettingsLabeledRow("Mô hình") {
                Picker("Mô hình", selection: Binding(
                    get: { session.maziaoModel },
                    set: { session.selectMaziaoModel($0) }
                )) {
                    ForEach(MaziaoDubbingModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            DubbingSettingsLabeledRow("Giọng nói") {
                DubbingSearchableVoicePicker(
                    selection: Binding(
                        get: { session.maziaoVoiceIdentifier },
                        set: { session.selectMaziaoVoice($0) }
                    ),
                    voices: maziaoVoiceItems,
                    isLoading: isRefreshingMaziao || session.isRefreshingMaziaoVoices,
                    emptyTitle: "Chưa tải danh sách giọng",
                    showsSyncSummary: !session.maziaoVoices.isEmpty
                )
                .frame(maxWidth: 380)
            }

            catalogError(session.maziaoVoiceCatalogError)
            catalogSummary(
                count: session.maziaoVoices.count,
                isRefreshing: isRefreshingMaziao || session.isRefreshingMaziaoVoices,
                enabled: session.hasCredential(for: .maziao)
            ) { await refreshMaziao() }

            DubbingCredentialEditor(
                placeholder: "Maziao API key",
                draft: $maziaoKeyDraft,
                hasKey: session.hasCredential(for: .maziao),
                save: saveMaziaoKey,
                remove: removeMaziaoKey
            )

            maziaoUsageCard

            DubbingExternalLinkButton(
                title: L10n.format("Xem mẫu giọng %@ trên web", session.maziaoModel.label),
                url: "https://app.maziao.com/?utm_campaign=see_all_voices&utm_medium=voice_demo&utm_source=media_support_master"
            )

            Text("Maziao hỗ trợ thư viện giọng đa ngôn ngữ. Nội dung cue chỉ được gửi khi bạn bấm tạo giọng.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)

            HStack(spacing: 8) {
                DubbingExternalLinkButton(title: "Mở API key Maziao", url: "https://app.maziao.com/profile?tab=api-keys")
                DubbingExternalLinkButton(title: "Tài liệu API", url: "https://app.maziao.com/api-docs")
            }
        }
    }

    private var googleCard: some View {
        DubbingSettingsCard(title: "Google Cloud TTS", icon: "cloud.fill", connected: session.hasCredential(for: .googleCloud), feedback: feedback) {
            DubbingSettingsLabeledRow("Mô hình") {
                Picker("Mô hình", selection: $session.googleModel) {
                    ForEach(GoogleDubbingModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            DubbingSettingsLabeledRow("Giọng nói") {
                DubbingSearchableVoicePicker(
                    selection: Binding(
                        get: { session.googleVoiceIdentifier },
                        set: { session.selectGoogleVoice($0) }
                    ),
                    voices: googleVoiceItems,
                    isLoading: session.isRefreshingGoogleVoices,
                    emptyTitle: "Chưa tải danh sách giọng",
                    showsSyncSummary: !session.googleVoices.isEmpty
                )
                .frame(maxWidth: 380)
            }

            catalogError(session.googleVoiceCatalogError)
            catalogSummary(
                count: session.googleVoices.count,
                isRefreshing: session.isRefreshingGoogleVoices,
                enabled: session.hasCredential(for: .googleCloud)
            ) { await session.refreshGoogleVoiceCatalog() }

            DubbingCredentialEditor(
                placeholder: "Google API key",
                draft: $googleKeyDraft,
                hasKey: session.hasCredential(for: .googleCloud),
                save: saveGoogleKey,
                remove: removeGoogleKey
            )

            googleUsageCard

            DubbingExternalLinkButton(
                title: L10n.format("Xem mẫu giọng %@ trên web", session.googleModel.label),
                url: "https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types"
            )

            Text("Google là lựa chọn ưu tiên. Hạn mức miễn phí phụ thuộc tài khoản Cloud và cần bật Text-to-Speech API.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)

            DubbingExternalLinkButton(title: "Mở Google Cloud Console", url: "https://console.cloud.google.com/apis/credentials")
        }
    }

    private var elevenCard: some View {
        DubbingSettingsCard(title: "ElevenLabs", icon: "waveform.badge.sparkles", connected: session.hasCredential(for: .elevenLabs), feedback: feedback) {
            DubbingSettingsLabeledRow("Mô hình") {
                Picker("Mô hình", selection: $session.elevenModel) {
                    ForEach(ElevenLabsDubbingModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Giọng nói")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.mutedText)
                DubbingSearchableVoicePicker(
                    selection: Binding(
                        get: { session.elevenVoiceIdentifier },
                        set: { session.selectElevenVoice($0) }
                    ),
                    voices: elevenVoiceItems,
                    isLoading: session.isRefreshingElevenVoices,
                    emptyTitle: "Chưa tải danh sách giọng",
                    showsSyncSummary: !session.elevenVoices.isEmpty
                )
                .frame(maxWidth: 460)
                TextField(L10n.string("Hoặc nhập Voice ID thủ công"), text: $session.elevenVoiceIdentifier)
                    .textFieldStyle(.plain)
                    .font(AppFont.mono)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppFieldSurface(radius: 8))
            }

            catalogError(session.elevenVoiceCatalogError)
            catalogSummary(
                count: session.elevenVoices.count,
                isRefreshing: session.isRefreshingElevenVoices,
                enabled: session.hasCredential(for: .elevenLabs)
            ) { await session.refreshElevenVoiceCatalog() }

            DubbingCredentialEditor(
                placeholder: "ElevenLabs API key",
                draft: $elevenKeyDraft,
                hasKey: session.hasCredential(for: .elevenLabs),
                save: saveElevenKey,
                remove: removeElevenKey
            )

            elevenUsageCard

            DubbingExternalLinkButton(
                title: L10n.format("Xem mẫu giọng %@ trên web", session.elevenModel.label),
                url: "https://elevenlabs.io/app/voice-library"
            )

            Text("Eleven v3 cho giọng biểu cảm hơn; Flash v2.5 nhẹ và nhanh hơn. Nội dung cue chỉ được gửi khi bạn bấm tạo giọng.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)

            DubbingExternalLinkButton(title: "Mở ElevenLabs", url: "https://elevenlabs.io/app/settings/api-keys")
        }
    }

    private var appleCard: some View {
        DubbingSettingsCard(title: "Apple Offline", icon: "desktopcomputer", connected: !session.voices.isEmpty, feedback: feedback) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.accentGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.format("Đã tìm thấy %d giọng trên máy", session.voices.count))
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.headlineText)
                    Text("Ứng dụng chỉ liệt kê giọng đã cài trong macOS. Không tải thêm và không gửi nội dung ra ngoài.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }

            DubbingSettingsLabeledRow("Giọng nói") {
                DubbingSearchableVoicePicker(
                    selection: appleVoiceBinding,
                    voices: appleVoiceItems,
                    isLoading: false,
                    emptyTitle: "Chưa chọn giọng",
                    showsSyncSummary: false
                )
                .frame(maxWidth: 380)
            }

            Label("Không giới hạn · xử lý trên máy", systemImage: "infinity")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.accentGreen)

            voicePreviewRow(
                enabled: session.selectedVoiceIdentifier != nil,
                detail: "Phát trực tiếp trên máy · không dùng API."
            )

            DubbingExternalLinkButton(
                title: "Xem hướng dẫn giọng Apple",
                url: "https://support.apple.com/guide/mac-help/change-the-voice-your-mac-uses-to-speak-text-mchlp2290/mac"
            )
        }
    }

    private func voicePreviewRow(
        enabled: Bool,
        detail: String,
        buttonTitle: String = "Nghe thử giọng"
    ) -> some View {
        let provider = DubbingSpeechProvider.appleOffline
        let isActive = voicePreview.activeProvider == provider
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                AppPillButton(
                    title: isActive && voicePreview.isPlaying
                        ? "Dừng nghe"
                        : (isActive && voicePreview.isBusy ? "Đang chuẩn bị…" : buttonTitle),
                    icon: isActive && voicePreview.isPlaying ? "stop.fill" : "play.fill",
                    tint: isActive && voicePreview.isPlaying ? AppTheme.accentOrange : AppTheme.accentGreen,
                    filled: false,
                    disabled: !enabled || (voicePreview.isBusy && !isActive)
                ) {
                    if isActive && (voicePreview.isPlaying || voicePreview.isBusy) {
                        voicePreview.stop()
                    } else {
                        Task {
                            await voicePreview.play(sampleRequest())
                        }
                    }
                }

                Text(L10n.string(enabled ? detail : "Chưa nhập key hoặc chọn giọng."))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isActive, !voicePreview.errorMessage.isEmpty {
                Text(voicePreview.errorMessage)
                    .textSelection(.enabled)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sampleRequest() -> DubbingSpeechRequest {
        let locale = session.languageIdentifier
        return DubbingSpeechRequest(
            cueID: -1,
            text: sampleText(for: locale),
            localeIdentifier: locale,
            voiceIdentifier: session.voiceIdentifier,
            rate: session.speechRate,
            outputURL: FileManager.default.temporaryDirectory.appendingPathComponent("msm-voice-preview.caf"),
            provider: .appleOffline,
            modelIdentifier: "apple-system"
        )
    }

    private var googleVoiceItems: [DubbingVoiceCatalogItem] {
        session.googleVoicesForSelectedModel.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: DubbingVoiceCatalogPolicy.localizedGender($0.gender))
        }
    }

    private var maziaoVoiceItems: [DubbingVoiceCatalogItem] {
        session.maziaoVoicesForSelectedModel.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: DubbingVoiceCatalogPolicy.localizedGender($0.gender))
        }
    }

    private var elevenVoiceItems: [DubbingVoiceCatalogItem] {
        session.elevenVoices.map {
            let detail = [DubbingVoiceCatalogPolicy.localizedGender($0.gender), $0.category]
                .filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
            return DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: detail)
        }
    }

    private var appleVoiceItems: [DubbingVoiceCatalogItem] {
        session.voices.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: $0.qualityLabel)
        }
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { session.voiceIdentifier },
            set: { identifier in
                if let voice = session.voices.first(where: { $0.id == identifier }) {
                    session.languageIdentifier = voice.language
                }
                session.voiceIdentifier = identifier
            }
        )
    }

    @ViewBuilder
    private func catalogError(_ message: String) -> some View {
        if !message.isEmpty {
            Text(message)
                .textSelection(.enabled)
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.accentOrange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func catalogSummary(
        count: Int,
        isRefreshing: Bool,
        enabled: Bool,
        refresh: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack(spacing: 9) {
            if count > 0 {
                Text(L10n.format("API đã đồng bộ tổng cộng %d giọng.", count))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            Spacer(minLength: 0)
            AppPillButton(
                title: isRefreshing ? "Đang tải giọng…" : "Làm mới danh sách giọng",
                icon: "arrow.clockwise",
                tint: AppTheme.accentCyan,
                filled: false,
                disabled: !enabled || isRefreshing
            ) {
                Task { await refresh() }
            }
        }
    }

    private func sampleText(for locale: String) -> String {
        let language = locale.lowercased()
        if language.hasPrefix("ja") { return "こんにちは。これは音声のプレビューです。" }
        if language.hasPrefix("ko") { return "안녕하세요. 선택한 음성 미리 듣기입니다." }
        if language.hasPrefix("zh") { return "你好，这是所选语音的试听。" }
        if language.hasPrefix("en") { return "Hello. This is a preview of the selected voice." }
        return "Xin chào. Đây là bản nghe thử giọng bạn đã chọn."
    }

    private var googleUsageCard: some View {
        DubbingUsageSurface {
            Label("Hạn mức sử dụng", systemImage: "chart.bar.fill")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.headlineText)

            if session.hasCredential(for: .googleCloud) {
                Text(L10n.format("Đã gửi %@ ký tự qua app trong tháng này.", formattedNumber(googleUsage.charactersSent)))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Google không cho API key đọc tổng quota tài khoản.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                Text("Chưa nhập API key")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Nhập key để bắt đầu theo dõi lượng dùng trong app.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    private var elevenUsageCard: some View {
        DubbingUsageSurface {
            HStack(spacing: 8) {
                Label("Hạn mức sử dụng", systemImage: "gauge.with.dots.needle.33percent")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer(minLength: 0)
                if session.hasCredential(for: .elevenLabs) {
                    AppPillButton(
                        title: "Làm mới hạn mức",
                        icon: "arrow.clockwise",
                        tint: AppTheme.accentCyan,
                        filled: false,
                        disabled: isRefreshingElevenQuota
                    ) {
                        Task { await refreshElevenQuota() }
                    }
                }
            }

            if !session.hasCredential(for: .elevenLabs) {
                Text("Chưa nhập API key")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Nhập key để xem hạn mức tài khoản.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else if isRefreshingElevenQuota, elevenQuota == nil {
                ProgressView("Đang tải hạn mức…")
                    .controlSize(.small)
            } else if let quota = elevenQuota {
                ProgressView(value: quota.fractionUsed)
                    .tint(quota.fractionUsed > 0.9 ? AppTheme.accentOrange : AppTheme.accentCyan)
                Text(L10n.format(
                    "Còn %@ / %@ ký tự",
                    formattedNumber(quota.remainingCharacters),
                    formattedNumber(quota.characterLimit)
                ))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.headlineText)
                Text(L10n.format(
                    "Đã dùng %@ ký tự · reset %@",
                    formattedNumber(quota.usedCharacters),
                    quota.nextReset.map(formattedDate) ?? "—"
                ))
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
            }

            if !elevenQuotaError.isEmpty {
                Text(L10n.format("Không đọc được hạn mức: %@", elevenQuotaError))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var maziaoUsageCard: some View {
        DubbingUsageSurface {
            HStack(spacing: 8) {
                Label("Credit tài khoản", systemImage: "gauge.with.dots.needle.33percent")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer(minLength: 0)
                if session.hasCredential(for: .maziao) {
                    AppPillButton(
                        title: "Làm mới",
                        icon: "arrow.clockwise",
                        tint: AppTheme.accentCyan,
                        filled: false,
                        disabled: isRefreshingMaziao
                    ) { Task { await refreshMaziao() } }
                }
            }
            if !session.hasCredential(for: .maziao) {
                Text("Chưa nhập API key")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
            } else if isRefreshingMaziao, maziaoAccount == nil {
                ProgressView("Đang tải tài khoản…").controlSize(.small)
            } else if let account = maziaoAccount {
                Text(L10n.format("Còn %@ credit", formattedNumber(account.remainingCredits)))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text(L10n.format("Cập nhật %@", formattedDate(account.updatedAt)))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            if !maziaoError.isEmpty {
                Text(L10n.format("Không đọc được Maziao: %@", maziaoError))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Quyền riêng tư", systemImage: "lock.shield.fill")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.headlineText)
            Text("Khóa Google, Maziao và ElevenLabs được lưu trong Keychain. Với dịch vụ cloud, chỉ nội dung cue bạn yêu cầu tạo giọng mới được gửi tới nhà cung cấp đã chọn; ứng dụng không tự chuyển sang provider khác.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(14)
        .background(AppTileSurface())
    }

    @MainActor
    private func saveGoogleKey() async {
        let key = googleKeyDraft
        do {
            try await DubbingCredentialAccess.shared.saveGoogle(key)
            session.setCredentialAvailability(true, for: .googleCloud)
            googleKeyDraft = ""
            feedback = "Đã lưu Google API key trong Keychain."
            googleUsage = ProviderUsageStore.googleLocalUsage()
            await session.refreshGoogleVoiceCatalog()
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func removeGoogleKey() async {
        do {
            try await DubbingCredentialAccess.shared.deleteGoogle()
            session.setCredentialAvailability(false, for: .googleCloud)
            googleKeyDraft = ""
            feedback = "Đã xóa Google API key."
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func saveElevenKey() async {
        let key = elevenKeyDraft
        do {
            try await DubbingCredentialAccess.shared.saveElevenLabs(key)
            session.setCredentialAvailability(true, for: .elevenLabs)
            ProviderUsageStore.clearElevenLabs()
            elevenQuota = nil
            elevenQuotaError = ""
            elevenKeyDraft = ""
            feedback = "Đã lưu ElevenLabs API key trong Keychain."
            await session.refreshElevenVoiceCatalog()
            await refreshElevenQuota()
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func removeElevenKey() async {
        do {
            try await DubbingCredentialAccess.shared.deleteElevenLabs()
            session.setCredentialAvailability(false, for: .elevenLabs)
            ProviderUsageStore.clearElevenLabs()
            elevenQuota = nil
            elevenQuotaError = ""
            elevenKeyDraft = ""
            feedback = "Đã xóa ElevenLabs API key."
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func saveMaziaoKey() async {
        let key = maziaoKeyDraft
        do {
            try await DubbingCredentialAccess.shared.saveMaziao(key)
            session.setCredentialAvailability(true, for: .maziao)
            ProviderUsageStore.clearMaziao()
            maziaoAccount = nil
            session.clearMaziaoVoiceCatalog()
            maziaoError = ""
            maziaoKeyDraft = ""
            feedback = "Đã lưu Maziao API key trong Keychain."
            Task { await refreshMaziao() }
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func removeMaziaoKey() async {
        do {
            try await DubbingCredentialAccess.shared.deleteMaziao()
            session.setCredentialAvailability(false, for: .maziao)
            ProviderUsageStore.clearMaziao()
            maziaoAccount = nil
            session.clearMaziaoVoiceCatalog()
            maziaoError = ""
            maziaoKeyDraft = ""
            session.maziaoVoiceIdentifier = ""
            feedback = "Đã xóa Maziao API key."
        } catch { feedback = error.localizedDescription }
    }

    @MainActor
    private func refreshMaziao() async {
        guard session.hasCredential(for: .maziao), !isRefreshingMaziao else { return }
        isRefreshingMaziao = true
        maziaoError = ""
        defer { isRefreshingMaziao = false }
        do {
            async let account = MaziaoAPIClient.account()
            await session.refreshMaziaoVoiceCatalog()
            maziaoAccount = try await account
            if !session.maziaoVoiceCatalogError.isEmpty {
                maziaoError = session.maziaoVoiceCatalogError
            }
        } catch {
            if let dubbingError = error as? DubbingError,
               case .missingCredential = dubbingError {
                session.setCredentialAvailability(false, for: .maziao)
            }
            maziaoError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshElevenQuota() async {
        guard session.hasCredential(for: .elevenLabs), !isRefreshingElevenQuota else { return }
        isRefreshingElevenQuota = true
        elevenQuotaError = ""
        defer { isRefreshingElevenQuota = false }
        do {
            elevenQuota = try await ElevenLabsQuotaService.refresh()
        } catch {
            if let dubbingError = error as? DubbingError,
               case .missingCredential = dubbingError {
                session.setCredentialAvailability(false, for: .elevenLabs)
            }
            elevenQuotaError = error.localizedDescription
        }
    }

    private func formattedNumber(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
