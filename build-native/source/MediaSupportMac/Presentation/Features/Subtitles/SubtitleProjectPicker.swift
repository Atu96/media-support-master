import SwiftUI

// MARK: - Dự án gần đây (tab tạo sub)

struct SubtitleRecentProjectsOverlay: View {
    let entries: [ProjectBackupIndexEntry]
    let selectedPath: String?
    @Binding var isExpanded: Bool
    /// true = nằm trên khung drop (nét đứt) thay vì phủ full card.
    var stackedBelowBar: Bool = false
    let onOpen: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dự án gần đây")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(AppTheme.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: isExpanded ? 0 : 8, style: .continuous)
                        .fill(AppTheme.tileFill.opacity(isExpanded ? 0.98 : 0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: isExpanded ? 0 : 8, style: .continuous)
                                .stroke(AppTheme.tileStroke, lineWidth: 0.75)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 8, style: .continuous))
            }
            .buttonStyle(AppPlainButtonStyle())
            .padding(stackedBelowBar ? 0 : (isExpanded ? 0 : 8))

            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry: entry)
                            if entry.id != entries.last?.id {
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: stackedBelowBar ? 160 : .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: stackedBelowBar ? nil : .infinity, alignment: .top)
        .background {
            if isExpanded {
                AppTileSurface(radius: stackedBelowBar ? 0 : 10)
                    .opacity(0.98)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: stackedBelowBar ? 0 : 10, style: .continuous))
    }

    private func row(entry: ProjectBackupIndexEntry) -> some View {
        let selected = selectedPath == entry.mediaPath

        return HStack(spacing: 8) {
            Text(entry.displayName)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppTheme.headlineText : AppTheme.bodyText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.accentBlue)
            }

            overlayActionButton(title: "Mở", tint: AppTheme.accentBlue) {
                onOpen(entry.mediaPath)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded = false
                }
            }

            overlayActionButton(title: "Xóa", tint: AppTheme.accentOrange) {
                onDelete(entry.mediaPath)
                if entries.count <= 1 {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded = false
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(selected ? AppTheme.accentBlue.opacity(0.1) : Color.clear)
    }

    private func overlayActionButton(
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(tint.opacity(0.35), lineWidth: 0.75)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(AppPlainButtonStyle())
    }
}

// MARK: - Chuyển dự án (tab chỉnh sửa)

struct SubtitleEditProjectBar: View {
    @ObservedObject var viewModel: SubtitleViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accentBlue)

            Text(activeTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.headlineText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            projectMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.tileStroke, lineWidth: 0.75)
                )
        )
    }

    private var activeTitle: String {
        viewModel.mediaURL?.lastPathComponent ?? "Chưa chọn video"
    }

    private var projectMenu: some View {
        Menu {
            let entries = viewModel.editableProjectEntries()
            if entries.isEmpty {
                Text("Chưa có dự án có SRT")
            } else {
                ForEach(entries) { entry in
                    Button {
                        viewModel.openRecentProject(at: entry.mediaPath)
                    } label: {
                        projectMenuLabel(entry: entry)
                    }
                }
            }

            Divider()

            Button {
                FilePickerHelper.pickFile(allowedTypes: FilePickerHelper.mediaTypes) {
                    viewModel.setMediaURL($0)
                }
            } label: {
                Label("Chọn video khác…", systemImage: "folder")
            }

            Button {
                FilePickerHelper.pickFile(allowedTypes: [FilePickerHelper.srtType]) {
                    viewModel.setSRTURL($0)
                }
            } label: {
                Label("Chọn SRT…", systemImage: "doc.text")
            }
        } label: {
            HStack(spacing: 5) {
                Text("Dự án")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(AppTheme.accentBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.accentBlue.opacity(0.1))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.accentBlue.opacity(0.28), lineWidth: 0.75)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func projectMenuLabel(entry: ProjectBackupIndexEntry) -> some View {
        let selected = viewModel.mediaURL?.path == entry.mediaPath
        let badge = viewModel.projectSubtitleSummary(for: entry)

        if let badge {
            if selected {
                Label {
                    Text("\(entry.displayName) · \(badge)")
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                Text("\(entry.displayName) · \(badge)")
            }
        } else if selected {
            Label(entry.displayName, systemImage: "checkmark")
        } else {
            Text(entry.displayName)
        }
    }
}