import AppKit
import SwiftUI

struct SettingsGeminiKeyPanel: View {
    private static let googleAPIKeyURL = URL(string: "https://aistudio.google.com/apikey")!
    @ObservedObject private var preferences = SubtitlePreferences.shared

    @State private var isEditing = false
    @State private var draftKey = ""
    @State private var feedback = ""

    private var hasKey: Bool { GeminiCredentialStore.hasKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            obtainKeyCard

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(hasKey ? AppTheme.accentGreen.opacity(0.16) : AppTheme.accentOrange.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "key.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hasKey ? AppTheme.accentGreen : AppTheme.accentOrange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(hasKey ? "Gemini đã được kết nối" : "Chưa kết nối Gemini"))
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Text(L10n.string(preferences.geminiQuotaExceeded
                    ? "Khóa hiện tại đã hết hạn mức. Hãy thay khóa để tiếp tục."
                    : "Khóa API được lưu an toàn trong Keychain."))
                    .font(AppFont.caption)
                    .foregroundStyle(preferences.geminiQuotaExceeded ? AppTheme.accentOrange : AppTheme.mutedText)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(hasKey ? AppTheme.accentGreen : AppTheme.accentOrange)
                .frame(width: 8, height: 8)
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var obtainKeyCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accentBlue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Google AI Studio")
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                Text("Tạo khóa API trong Google AI Studio rồi dán vào ứng dụng.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer(minLength: 8)

            AppPillButton(
                title: "Mở Google AI Studio",
                icon: "arrow.up.forward",
                tint: AppTheme.accentBlue,
                filled: false,
                action: openGoogleAPIKeyPage
            )
        }
        .padding(14)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Khóa API Gemini")
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)

            SecureField("AIza…", text: $draftKey)
                .textFieldStyle(.plain)
                .font(AppFont.mono)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppFieldSurface(radius: 10))

            HStack(spacing: 10) {
                AppPillButton(
                    title: "Lưu",
                    icon: "checkmark",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: saveKey
                )
                AppPillButton(
                    title: "Huỷ",
                    icon: "xmark",
                    tint: AppTheme.mutedText,
                    filled: false,
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
                    title: "Kết nối Gemini",
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

    private func openGoogleAPIKeyPage() {
        NSWorkspace.shared.open(Self.googleAPIKeyURL)
    }

    private func beginEditing() {
        draftKey = ""
        feedback = ""
        isEditing = true
    }

    private func cancelEditing() {
        draftKey = ""
        isEditing = false
    }

    private func saveKey() {
        do {
            try GeminiCredentialStore.save(draftKey)
            preferences.clearGeminiQuotaExceeded()
            feedback = "Đã kết nối Gemini."
            isEditing = false
            draftKey = ""
            Task { await preferences.refreshEngineStatus() }
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try GeminiCredentialStore.delete()
            preferences.clearGeminiQuotaExceeded()
            feedback = "Đã ngắt kết nối Gemini."
            isEditing = false
            draftKey = ""
            Task { await preferences.refreshEngineStatus() }
        } catch {
            feedback = error.localizedDescription
        }
    }
}
