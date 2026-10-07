import AppKit
import SwiftUI

struct SettingsGroqKeyPanel: View {
    private static let groqAPIKeyURL = URL(string: "https://console.groq.com/keys")!
    private static let groqLimitsURL = URL(string: "https://console.groq.com/settings/limits")!

    @ObservedObject private var preferences = SubtitlePreferences.shared
    @AppStorage(GroqModelPreferences.textModelKey)
    private var textModelRaw = GroqTextModel.quality.rawValue
    @AppStorage(GroqModelPreferences.speechModelKey)
    private var speechModelRaw = GroqSpeechModel.turbo.rawValue
    @AppStorage(GroqModelPreferences.semanticCuePlanningKey)
    private var semanticCuePlanningEnabled = true

    @State private var isEditing = false
    @State private var hasKey = GroqCredentialStore.hasKey
    @State private var isVerifyingKey = false
    @State private var isRefreshingUsage = false
    @State private var draftKey = ""
    @State private var feedback = ""
    @State private var usageSnapshot = ProviderUsageStore.groqSnapshot()
    @State private var connectionSnapshot = ProviderUsageStore.groqConnectionSnapshot()

    private var selectedTextModel: GroqTextModel {
        GroqTextModel(rawValue: textModelRaw) ?? .quality
    }
    private var selectedSpeechModel: GroqSpeechModel {
        GroqSpeechModel(rawValue: speechModelRaw) ?? .turbo
    }
    private var hasVerifiedConnection: Bool {
        hasKey && connectionSnapshot != nil
    }
    private var connectionTint: Color {
        if isVerifyingKey { return AppTheme.accentCyan }
        return hasVerifiedConnection ? AppTheme.accentGreen : AppTheme.accentOrange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                usageCard
                modelCard
                guideCard

                if isEditing {
                    editorCard
                } else {
                    actionCard
                }

                if !feedback.isEmpty {
                    Text(L10n.string(feedback))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            hasKey = GroqCredentialStore.hasKey
            usageSnapshot = ProviderUsageStore.groqSnapshot()
            connectionSnapshot = ProviderUsageStore.groqConnectionSnapshot()
            if hasKey, connectionSnapshot == nil {
                verifyStoredKey()
            }
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Hạn mức sử dụng", systemImage: "gauge.with.dots.needle.33percent")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer(minLength: 0)
                AppPillButton(
                    title: isRefreshingUsage ? "Đang tải hạn mức…" : "Làm mới hạn mức",
                    icon: isRefreshingUsage ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise",
                    tint: AppTheme.accentCyan,
                    filled: false,
                    disabled: !hasKey || isVerifyingKey || isRefreshingUsage,
                    action: refreshUsage
                )
                AppPillButton(
                    title: "Mở hạn mức Groq",
                    icon: "arrow.up.forward",
                    tint: AppTheme.accentCyan,
                    filled: false,
                    action: { NSWorkspace.shared.open(Self.groqLimitsURL) }
                )
            }

            if !hasKey {
                Text("Chưa nhập API key")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Nhập key để nhận dữ liệu sau tác vụ Groq đầu tiên.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else if isRefreshingUsage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang đọc hạn mức từ Groq…")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.headlineText)
                }
            } else if isVerifyingKey {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang xác thực API key với Groq…")
                        .font(AppFont.body)
                        .foregroundStyle(AppTheme.headlineText)
                }
            } else if let usageSnapshot {
                if let modelID = usageSnapshot.modelID {
                    Text(L10n.format("Mô hình hạn mức: %@", modelLabel(for: modelID)))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                if let remaining = usageSnapshot.remainingRequests, let limit = usageSnapshot.requestLimit {
                    Text(L10n.format(
                        "Còn %@ / %@ request mỗi ngày",
                        formattedNumber(remaining),
                        formattedNumber(limit)
                    ))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                }
                if let remaining = usageSnapshot.remainingTokens, let limit = usageSnapshot.tokenLimit {
                    Text(L10n.format(
                        "Còn %@ / %@ token mỗi phút",
                        formattedNumber(remaining),
                        formattedNumber(limit)
                    ))
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                }
                if let reset = usageSnapshot.requestReset {
                    Text(L10n.format("Reset request: %@", reset))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                if let reset = usageSnapshot.tokenReset {
                    Text(L10n.format("Reset token: %@", reset))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Text(L10n.format("Cập nhật lúc %@", formattedDate(usageSnapshot.updatedAt)))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                Text("Chưa có dữ liệu hạn mức.")
                    .font(AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                Text(connectionSnapshot == nil
                    ? "Groq cập nhật sau tác vụ tiếp theo."
                    : "Key đã được Groq xác thực; hạn mức sẽ cập nhật sau tác vụ tiếp theo.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Text("Groq không có hạn mức theo ký tự.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
            if hasKey {
                Text(L10n.format(
                    "Mỗi lần làm mới gửi 1 ký tự; Groq vẫn tính token giao thức và tối đa 1 token đầu ra cho %@.",
                    selectedTextModel.label
                ))
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(connectionTint.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(connectionTint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(statusTitle))
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Text(L10n.string(statusDetail))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(connectionTint)
                .frame(width: 8, height: 8)
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mô hình mặc định")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)

            modelPicker(
                title: "Dịch và tóm tắt",
                selection: $textModelRaw,
                options: GroqTextModel.allCases.map { ($0.rawValue, L10n.string($0.menuLabel)) },
                detail: L10n.string(selectedTextModel.detail)
            )

            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)

            modelPicker(
                title: "Chép lời và tạo phụ đề",
                selection: $speechModelRaw,
                options: GroqSpeechModel.allCases.map { ($0.rawValue, L10n.string($0.menuLabel)) },
                detail: L10n.string(selectedSpeechModel.detail)
            )

            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)

            Toggle(isOn: $semanticCuePlanningEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hiểu ngữ cảnh khi ngắt câu")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.headlineText)
                    Text("Chỉ gửi các cụm từ mơ hồ cho mô hình văn bản Groq. AI chỉ chọn ranh giới; ứng dụng giữ nguyên chữ và thời gian.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func modelPicker(
        title: String,
        selection: Binding<String>,
        options: [(id: String, label: String)],
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(title))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)

            Picker(title, selection: selection) {
                ForEach(options, id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 340, alignment: .leading)

            Text(L10n.string(detail))
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guideCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accentCyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("Tạo khóa API")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Mở Groq Console, tạo khóa mới rồi dán vào ứng dụng.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer(minLength: 8)

            AppPillButton(
                title: "Mở Groq Console",
                icon: "arrow.up.forward",
                tint: AppTheme.accentCyan,
                filled: false,
                action: openGroqAPIKeyPage
            )
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Khóa API Groq")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)

            SecureField("gsk_…", text: $draftKey)
                .textFieldStyle(.plain)
                .font(AppFont.mono)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppFieldSurface(radius: 8))

            HStack(spacing: 10) {
                AppPillButton(
                    title: isVerifyingKey ? "Đang xác thực…" : "Lưu",
                    icon: isVerifyingKey ? "arrow.trianglehead.2.clockwise.rotate.90" : "checkmark",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifyingKey,
                    action: saveKey
                )
                AppPillButton(
                    title: "Huỷ",
                    icon: "xmark",
                    tint: AppTheme.mutedText,
                    filled: false,
                    disabled: isVerifyingKey,
                    action: cancelEditing
                )
            }
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var actionCard: some View {
        HStack(spacing: 10) {
            if hasKey {
                AppPillButton(
                    title: "Thay khóa",
                    icon: "pencil",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    action: beginEditing
                )
                AppPillButton(
                    title: "Ngắt kết nối",
                    icon: "trash",
                    tint: AppTheme.accentRed,
                    filled: false,
                    action: deleteKey
                )
            } else {
                AppPillButton(
                    title: "Kết nối Groq",
                    icon: "key.fill",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    action: beginEditing
                )
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func openGroqAPIKeyPage() {
        NSWorkspace.shared.open(Self.groqAPIKeyURL)
    }

    private func beginEditing() {
        draftKey = ""
        feedback = ""
        isEditing = true
    }

    private func cancelEditing() {
        guard !isVerifyingKey else { return }
        draftKey = ""
        isEditing = false
    }

    private func saveKey() {
        guard !isVerifyingKey else { return }
        let candidate = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        isVerifyingKey = true
        feedback = "Đang xác thực API key với Groq…"
        Task {
            do {
                let verification = try await GroqConnectionVerifier.verify(apiKey: candidate)
                try GroqCredentialStore.save(candidate)

                let connection = GroqConnectionSnapshot(
                    availableModelCount: verification.availableModelCount,
                    verifiedAt: Date()
                )
                ProviderUsageStore.clearGroq()
                ProviderUsageStore.clearGroqConnection()
                if let snapshot = verification.usageSnapshot {
                    ProviderUsageStore.saveGroq(snapshot)
                }
                ProviderUsageStore.saveGroqConnection(connection)

                hasKey = true
                usageSnapshot = verification.usageSnapshot
                connectionSnapshot = connection
                feedback = "Đã xác thực và cập nhật API key Groq."
                isEditing = false
                draftKey = ""
                await preferences.refreshEngineStatus()
            } catch {
                feedback = error.localizedDescription
            }
            isVerifyingKey = false
        }
    }

    private func verifyStoredKey() {
        guard hasKey, !isVerifyingKey else { return }
        let storedKey = GroqCredentialStore.load()
        guard !storedKey.isEmpty else {
            hasKey = false
            return
        }

        isVerifyingKey = true
        feedback = "Đang xác thực API key với Groq…"
        Task {
            do {
                let verification = try await GroqConnectionVerifier.verify(apiKey: storedKey)
                let connection = GroqConnectionSnapshot(
                    availableModelCount: verification.availableModelCount,
                    verifiedAt: Date()
                )
                if let snapshot = verification.usageSnapshot {
                    ProviderUsageStore.saveGroq(snapshot)
                    usageSnapshot = snapshot
                }
                ProviderUsageStore.saveGroqConnection(connection)
                connectionSnapshot = connection
                feedback = "API key Groq đang hoạt động."
            } catch let error as GroqConnectionVerificationError {
                if error == .rejectedKey {
                    ProviderUsageStore.clearGroq()
                    ProviderUsageStore.clearGroqConnection()
                    usageSnapshot = nil
                    connectionSnapshot = nil
                }
                feedback = error.localizedDescription
            } catch {
                feedback = error.localizedDescription
            }
            isVerifyingKey = false
        }
    }

    private func refreshUsage() {
        guard hasKey, !isVerifyingKey, !isRefreshingUsage else { return }
        let storedKey = GroqCredentialStore.load()
        guard !storedKey.isEmpty else {
            hasKey = false
            return
        }

        let model = selectedTextModel
        isRefreshingUsage = true
        feedback = "Đang đọc hạn mức từ Groq…"
        Task {
            do {
                let snapshot = try await GroqUsageLimitService.refresh(
                    apiKey: storedKey,
                    model: model
                )
                usageSnapshot = snapshot
                feedback = L10n.format("Đã cập nhật hạn mức Groq cho %@.", model.label)
            } catch let error as GroqConnectionVerificationError {
                if error == .rejectedKey {
                    ProviderUsageStore.clearGroq()
                    ProviderUsageStore.clearGroqConnection()
                    usageSnapshot = nil
                    connectionSnapshot = nil
                }
                feedback = error.localizedDescription
            } catch {
                feedback = error.localizedDescription
            }
            isRefreshingUsage = false
        }
    }

    private func deleteKey() {
        do {
            try GroqCredentialStore.delete()
            ProviderUsageStore.clearGroq()
            ProviderUsageStore.clearGroqConnection()
            hasKey = false
            usageSnapshot = nil
            connectionSnapshot = nil
            feedback = "Đã ngắt kết nối Groq."
            isEditing = false
            draftKey = ""
            Task { await preferences.refreshEngineStatus() }
        } catch {
            feedback = error.localizedDescription
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

    private func modelLabel(for modelID: String) -> String {
        if let textModel = GroqTextModel(rawValue: modelID) { return textModel.label }
        if let speechModel = GroqSpeechModel(rawValue: modelID) { return speechModel.shortLabel }
        return modelID
    }

    private var statusDetail: String {
        if isVerifyingKey {
            return "Đang xác thực API key với Groq…"
        }
        if let connectionSnapshot {
            return L10n.format("Key đã được Groq xác thực lúc %@.", formattedDate(connectionSnapshot.verifiedAt))
        }
        return "Khóa API được lưu an toàn trong Keychain."
    }

    private var statusTitle: String {
        if isVerifyingKey { return "Đang kiểm tra kết nối Groq" }
        if hasVerifiedConnection { return "Groq đã được kết nối" }
        return hasKey ? "Groq chưa được xác thực" : "Chưa kết nối Groq"
    }
}
