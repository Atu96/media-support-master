import SwiftUI

/// Ô chọn media + dự án gần đây + nút chạy — dùng chung tab Tạo sub tự động & Khớp văn bản gốc.
struct SubtitleDraftMediaCard: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var runner = MediaEngineService.shared.runner
    let tab: SubtitleModuleTab
    let rowHeight: CGFloat
    let runTitle: String
    let runIcon: String
    let isRunning: Bool
    let canRun: Bool
    let onRun: () -> Void

    @State private var showRecentProjects = false
    @State private var showOCR = false

    private var draftURL: URL? {
        switch tab {
        case .create: viewModel.whisperDraftMediaURL
        case .script: viewModel.scriptDraftMediaURL
        }
    }

    private var isAutomaticCreate: Bool { tab == .create }

    private var isStandaloneSRT: Bool {
        isAutomaticCreate
            && viewModel.mediaURL == nil
            && viewModel.whisperDraftMediaURL == nil
            && viewModel.srtURL != nil
    }

    private var hasExistingSRTForDraft: Bool {
        guard isAutomaticCreate,
              let draft = viewModel.whisperDraftMediaURL,
              viewModel.isActiveProject(draft) else { return false }
        return viewModel.srtURL != nil && !viewModel.segments.isEmpty
    }

    private var displayedSourceName: String? {
        isStandaloneSRT ? viewModel.srtURL?.lastPathComponent : draftURL?.lastPathComponent
    }

    var body: some View {
        let recentEntries = viewModel.recentCreateTabEntries(for: tab)

        VStack(spacing: AppTheme.workspaceCellStackGap) {
            VStack(spacing: 0) {
                if !recentEntries.isEmpty {
                    SubtitleRecentProjectsOverlay(
                        entries: recentEntries,
                        selectedPath: draftURL?.path,
                        isExpanded: $showRecentProjects,
                        stackedBelowBar: true,
                        onOpen: { openRecent(path: $0) },
                        onDelete: { viewModel.deleteRecentProject(at: $0) }
                    )
                }

                AppMediaDropZone(
                    filename: displayedSourceName,
                    dropKind: isAutomaticCreate ? .subtitleSource : .media,
                    compact: true,
                    fillVertical: true,
                    emptyIcon: isAutomaticCreate ? "captions.bubble.fill" : "film.stack",
                    emptyTitle: isAutomaticCreate ? "Kéo video hoặc file SRT" : nil,
                    emptyFormats: isAutomaticCreate ? "Video để chép lời · SRT để sửa ngay" : nil,
                    onChoose: {
                        showRecentProjects = false
                        let types = isAutomaticCreate
                            ? FilePickerHelper.mediaTypes + [FilePickerHelper.srtType]
                            : FilePickerHelper.mediaTypes
                        FilePickerHelper.pickFile(allowedTypes: types) { url in
                            applyDraft(url)
                        }
                    },
                    onDrop: { url in
                        showRecentProjects = false
                        applyDraft(url)
                    }
                )
                .frame(maxHeight: .infinity)
                .opacity(showRecentProjects && !recentEntries.isEmpty ? 0.35 : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            AppTheme.accentBlue.opacity(0.34),
                            style: StrokeStyle(lineWidth: 1.25, dash: [8, 5])
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if isAutomaticCreate, draftURL != nil, !isStandaloneSRT {
                AppFileDropField(
                    label: "SRT để chỉnh · không chép lời",
                    placeholder: "Tuỳ chọn — thả hoặc chọn file .srt",
                    filename: viewModel.srtURL?.lastPathComponent,
                    chooseTitle: viewModel.srtURL == nil ? "Chọn SRT" : "Đổi SRT",
                    dropKind: .srt,
                    onChoose: {
                        FilePickerHelper.pickFile(allowedTypes: [FilePickerHelper.srtType]) { url in
                            openExistingSRT(forSelectedVideo: url)
                        }
                    },
                    onDrop: { openExistingSRT(forSelectedVideo: $0) }
                )
            }

            if isStandaloneSRT {
                selectedSRTStatus
            } else {
                HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)
                if !hasExistingSRTForDraft {
                AppPillButton(
                    title: isRunning ? runningTitle : runTitle,
                    icon: runIcon,
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: !canRun || isRunning || runner.isRunning
                ) {
                    onRun()
                }
                }
                if isAutomaticCreate {
                    AppPillButton(title: "Lấy sub từ video", icon: "text.viewfinder", tint: AppTheme.accentBlue,
                                  filled: false, disabled: draftURL == nil || runner.isRunning) {
                        showOCR = true
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: AppTheme.workspaceTransportRowHeight)
            }
        }
        .padding(AppTheme.workspaceCellPadding)
        .frame(height: rowHeight)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .sheet(isPresented: $showOCR) {
            if let draftURL {
                SubtitleOCRConfigurationView(media: draftURL, controller: viewModel.ocrCreate,
                                              canRun: !viewModel.engine.isRunning)
            }
        }
    }

    private var runningTitle: String {
        switch tab {
        case .create: "Đang chép…"
        case .script: "Đang tạo…"
        }
    }

    private func applyDraft(_ url: URL) {
        switch tab {
        case .create:
            if url.pathExtension.lowercased() == "srt" {
                viewModel.openStandaloneSRT(url)
            } else {
                viewModel.setWhisperDraftMedia(url)
                viewModel.setMediaURL(url)
            }
        case .script:
            viewModel.setScriptDraftMedia(url)
            viewModel.syncPreviewForSubtitleTab(.script)
        }
    }

    private func openRecent(path: String) {
        switch tab {
        case .create:
            viewModel.openWhisperDraft(at: path)
        case .script:
            viewModel.openScriptDraft(at: path)
        }
    }

    private func openExistingSRT(forSelectedVideo url: URL) {
        guard let video = viewModel.whisperDraftMediaURL else { return }
        if !viewModel.isActiveProject(video) {
            viewModel.setMediaURL(video)
        }
        viewModel.openExistingSRT(url, mediaAlreadySet: true)
    }

    private var selectedSRTStatus: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accentGreen)
            Text("Đang sửa SRT — có thể xuất SRT mới")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.workspaceTransportRowHeight)
        .padding(.horizontal, 8)
        .background(AppTheme.accentGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
