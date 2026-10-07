import SwiftUI

/// Tab **Tạo sub tự động** — slots trên shell chung.
struct SubtitleCreateView: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var preview = AVPreviewService.shared

    var body: some View {
        SubtitleCreateWorkspaceShell(viewModel: viewModel) { rowHeight in
            mediaInputCard(rowHeight: rowHeight)
        } bottomLeftSlot: { rowHeight in
            summaryCard(rowHeight: rowHeight)
        } previewSlot: { rowHeight in
            previewPanel(rowHeight: rowHeight)
        } transcriptSlot: { rowHeight in
            transcriptPanel(rowHeight: rowHeight)
        } logSlot: {
            logSection
        }
    }

    // MARK: - Panels

    private func previewPanel(rowHeight: CGFloat) -> some View {
        // jobUI = đang chép lời (kể cả parse sau khi process thoát).
        let jobUI = viewModel.isWhisperJobInFlight || viewModel.isRunningWhisper
        let hasCues = !viewModel.segments.isEmpty
        // **Bug cũ:** `showsTranscript && !jobUI` → ẩn sub tới khi tắt job → “100% rồi mới phọt sub”.
        // Có cue là hiện list/overlay ngay; % vẫn hiện trên preview đến khi job xong.
        let showCues = hasCues || (viewModel.whisperTabShowsTranscript && !jobUI)
        let showOverlay = showCues && viewModel.showSubtitleOverlay
        // %: hiện khi job; tắt ngay khi đã có cue + complete (không giữ overlay che sub).
        let showProgress = jobUI && !(hasCues && viewModel.whisperComplete)

        return SubtitleWorkspacePanels.videoPreview(
            minHeight: rowHeight,
            frameHeight: rowHeight,
            preview: preview,
            segments: showCues ? viewModel.segments : [],
            style: viewModel.burnStyle,
            focusSegmentID: viewModel.previewFocusSegmentID,
            liveEditDraft: viewModel.liveEditDraft,
            showSubtitleOverlay: showOverlay,
            whisperProgressPercent: showProgress ? viewModel.whisperProgressPercent : nil
        )
    }

    @ViewBuilder
    private func transcriptPanel(rowHeight: CGFloat) -> some View {
        // Có cue hoặc tab đang job/xong → editor; không thì hướng dẫn đúng luồng tự động.
        let showEditor = !viewModel.segments.isEmpty || viewModel.whisperTabShowsTranscript
        Group {
            if showEditor {
                editableTranscriptPanel(height: rowHeight)
            } else {
                transcriptPlaceholder(height: rowHeight)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.segments.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRunningWhisper)
    }

    private func editableTranscriptPanel(height: CGFloat) -> some View {
        SubtitleTranscriptEditorHost(viewModel: viewModel)
            .padding(12)
            .frame(height: height)
            .background(AppTileSurface())
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func transcriptPlaceholder(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentBlue.opacity(0.09))
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.accentBlue)
            }
            .frame(width: 54, height: 54)
            Text("Timeline sẽ hiện sau khi chép lời")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.headlineText)
            Text("Chọn video để chép lời, hoặc thả SRT để mở timeline và sửa ngay.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    // MARK: - Left cells

    private func mediaInputCard(rowHeight: CGFloat) -> some View {
        SubtitleDraftMediaCard(
            viewModel: viewModel,
            tab: .create,
            rowHeight: rowHeight,
            runTitle: "Chép lời",
            runIcon: "waveform",
            isRunning: viewModel.isRunningWhisper,
            canRun: viewModel.canRunWhisper,
            onRun: { viewModel.runWhisper() }
        )
    }

    private func summaryCard(rowHeight: CGFloat) -> some View {
        let hasTranscript = viewModel.whisperTabShowsTranscript && !viewModel.segments.isEmpty
        let canSummarize = hasTranscript && viewModel.canRunSummary

        return VStack(alignment: .leading, spacing: 10) {
            Group {
                if viewModel.isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Đang tóm tắt…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if hasTranscript, !viewModel.transcriptSummary.isEmpty {
                    ScrollView {
                        Text(viewModel.transcriptSummary)
                            .font(AppFont.body)
                            .foregroundStyle(AppTheme.bodyText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: .infinity)
                } else if hasTranscript, let reason = viewModel.summaryDisabledReason {
                    Text(reason)
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.accentOrange)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                summaryActionButton(
                    title: viewModel.transcriptSummary.isEmpty ? "Tóm tắt" : "Tóm tắt lại",
                    icon: "text.alignleft",
                    disabled: !canSummarize || viewModel.isSummarizing
                ) {
                    Task { await viewModel.generateSummary() }
                }

                summaryActionButton(
                    title: "Sao chép",
                    icon: "doc.on.doc",
                    disabled: viewModel.transcriptSummary.isEmpty || viewModel.isSummarizing || !hasTranscript
                ) {
                    viewModel.copySummary()
                }
            }
        }
        .padding(12)
        .frame(height: rowHeight)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func summaryActionButton(
        title: String,
        icon: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accentBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.tileFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.tileStroke, lineWidth: 0.75)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(AppPressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var logSection: some View {
        LogConsoleView(
            runner: viewModel.runner,
            compactLines: 3,
            expandedLines: 12,
            startsExpanded: false,
            pinsToBottom: true,
            dockStyle: true,
            storageKey: "msm.logConsoleExpanded.create"
        )
    }
}
