import AppKit
import SwiftUI

/// Presentation-only building blocks shared by the dubbing provider cards.
/// They deliberately own no provider state, networking, Keychain access or tasks.
struct DubbingSettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let connected: Bool
    let feedback: String
    private let content: Content

    init(
        title: String,
        icon: String,
        connected: Bool,
        feedback: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.connected = connected
        self.feedback = feedback
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accentBlue)
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer(minLength: 0)
                Circle()
                    .fill(connected ? AppTheme.accentGreen : AppTheme.accentOrange)
                    .frame(width: 8, height: 8)
                Text(L10n.string(connected ? "Sẵn sàng" : "Chưa kết nối"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            content
            if !feedback.isEmpty {
                Text(L10n.string(feedback))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(14)
        .background(AppTileSurface())
    }
}

struct DubbingUsageSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppFieldSurface(radius: 9))
    }
}

struct DubbingCredentialEditor: View {
    let placeholder: String
    @Binding var draft: String
    let hasKey: Bool
    let save: () async -> Void
    let remove: () async -> Void
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(AppFont.mono)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppFieldSurface(radius: 8))
                .disabled(isWorking)
            HStack(spacing: 8) {
                AppPillButton(
                    title: isWorking ? "Đang lưu…" : (hasKey ? "Thay khóa" : "Lưu khóa"),
                    icon: "key.fill",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: isWorking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    guard !isWorking else { return }
                    isWorking = true
                    Task { @MainActor in
                        await save()
                        isWorking = false
                    }
                }
                if hasKey {
                    AppPillButton(
                        title: "Xóa khóa",
                        icon: "trash",
                        tint: AppTheme.accentRed,
                        filled: false,
                        disabled: isWorking
                    ) {
                        guard !isWorking else { return }
                        isWorking = true
                        Task { @MainActor in
                            await remove()
                            isWorking = false
                        }
                    }
                }
            }
        }
    }
}

struct DubbingSettingsLabeledRow<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.string(label))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 82, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct DubbingExternalLinkButton: View {
    let title: String
    let url: String

    var body: some View {
        AppPillButton(
            title: title,
            icon: "arrow.up.forward",
            tint: AppTheme.accentCyan,
            filled: false
        ) {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        }
    }
}

struct DubbingSearchableVoicePicker: View {
    @Binding var selection: String
    let voices: [DubbingVoiceCatalogItem]
    let isLoading: Bool
    let emptyTitle: String
    let showsSyncSummary: Bool
    @State private var query = ""

    private var allGroups: [DubbingVoiceCatalogGroup] {
        DubbingVoiceCatalogPolicy.groups(
            voices: voices,
            query: "",
            interfaceLocaleIdentifier: L10n.interfaceLocaleIdentifier
        )
    }

    private var filteredGroups: [DubbingVoiceCatalogGroup] {
        DubbingVoiceCatalogPolicy.groups(
            voices: voices,
            query: query,
            interfaceLocaleIdentifier: L10n.interfaceLocaleIdentifier
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(L10n.string("Tìm theo quốc gia hoặc tên giọng"), text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(AppFieldSurface(radius: AppTheme.editorControlRadius))

            if isLoading, voices.isEmpty {
                ProgressView(L10n.string("Đang tải giọng…"))
                    .controlSize(.small)
            } else if filteredGroups.isEmpty {
                Text(L10n.string(voices.isEmpty ? emptyTitle : "Không tìm thấy giọng phù hợp"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                Picker("Giọng nói", selection: $selection) {
                    ForEach(filteredGroups) { group in
                        Section("\(group.title) · \(group.voices.count)") {
                            ForEach(group.voices) { voice in
                                Text(voice.detail.isEmpty ? voice.name : "\(voice.name) · \(voice.detail)")
                                    .tag(voice.id)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if showsSyncSummary, !voices.isEmpty {
                Text(L10n.format("Đã đồng bộ %d giọng · %d nhóm ngôn ngữ", voices.count, allGroups.count))
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .help(L10n.string("Có thể tìm theo tên nước, ngôn ngữ, tên giọng hoặc mã giọng."))
    }
}
