import SwiftUI
import UniformTypeIdentifiers

/// Tab **Khớp văn bản gốc** — giữ nguyên chữ người dùng, lấy timing từ media.
struct SubtitleScriptCreateView: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var preview = AVPreviewService.shared

    var body: some View {
        SubtitleCreateWorkspaceShell(viewModel: viewModel) { rowHeight in
            mediaInputCard(rowHeight: rowHeight)
        } bottomLeftSlot: { rowHeight in
            scriptEditorCard(rowHeight: rowHeight)
        } previewSlot: { rowHeight in
            previewPanel(rowHeight: rowHeight)
        } transcriptSlot: { rowHeight in
            transcriptPanel(rowHeight: rowHeight)
        } logSlot: {
            logSection
        }
    }

    private func previewPanel(rowHeight: CGFloat) -> some View {
        let jobUI = viewModel.isScriptAlignJobInFlight || viewModel.isRunningScriptAlign
        let hasCues = !viewModel.segments.isEmpty
        // Có cue → hiện sub; % tắt khi đã complete (cùng pattern tab Whisper).
        let showCues = hasCues || (viewModel.scriptTabShowsTranscript && !jobUI)
        let showProgress = jobUI && !(hasCues && viewModel.whisperComplete)

        return SubtitleWorkspacePanels.videoPreview(
            minHeight: rowHeight,
            frameHeight: rowHeight,
            preview: preview,
            segments: showCues ? viewModel.segments : [],
            style: viewModel.burnStyle,
            focusSegmentID: viewModel.previewFocusSegmentID,
            liveEditDraft: viewModel.liveEditDraft,
            showSubtitleOverlay: showCues && viewModel.showSubtitleOverlay,
            whisperProgressPercent: showProgress ? viewModel.scriptAlignProgressPercent : nil
        )
    }

    @ViewBuilder
    private func transcriptPanel(rowHeight: CGFloat) -> some View {
        let showEditor = !viewModel.segments.isEmpty || viewModel.scriptTabShowsTranscript
        if showEditor {
            SubtitleTranscriptEditorHost(viewModel: viewModel)
                .padding(12)
                .frame(height: rowHeight)
                .background(AppTileSurface())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        } else {
            transcriptPlaceholder(height: rowHeight)
        }
    }

    private func transcriptPlaceholder(height: CGFloat) -> some View {
        // Tab văn bản: văn bản gốc → align, không import SRT có sẵn.
        Image(systemName: "text.alignleft")
            .font(.system(size: 28))
            .foregroundStyle(AppTheme.mutedText.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .frame(height: height)
            .background(AppTileSurface())
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func mediaInputCard(rowHeight: CGFloat) -> some View {
        SubtitleDraftMediaCard(
            viewModel: viewModel,
            tab: .script,
            rowHeight: rowHeight,
            runTitle: "Khớp thời gian",
            runIcon: "doc.text",
            isRunning: viewModel.isRunningScriptAlign,
            canRun: viewModel.canRunScriptAlign,
            onRun: { viewModel.runScriptAlign() }
        )
    }

    private func scriptEditorCard(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Văn bản gốc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.headlineText)

                Menu {
                    ForEach(ScriptAlignmentLanguage.allCases) { language in
                        Button(language.label) {
                            viewModel.scriptAlignmentLanguage = language
                        }
                    }
                } label: {
                    Text(L10n.string(viewModel.scriptAlignmentLanguage.label))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.bodyText)
                        .frame(minWidth: 116, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(AppFieldSurface(radius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: 0)

                Button {
                    importOriginalText()
                } label: {
                    Label("Nhập TXT", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Nhập lời bài hát, kịch bản hoặc bản chép lời chuẩn từ file TXT")

                if !viewModel.scriptText.isEmpty {
                    Button("Xóa") {
                        viewModel.scriptText = ""
                    }
                    .buttonStyle(AppPlainButtonStyle())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accentOrange)
                }
            }

            Text("Dán văn bản chuẩn; app giữ nguyên chữ và dùng âm thanh để khớp thời gian.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let message = viewModel.scriptLanguageDetectionMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accentBlue)
            }

            ZStack(alignment: .topLeading) {
                AppNSTextArea(text: $viewModel.scriptText, fontSize: 13)
                    .padding(4)


            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.tileFill.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.tileStroke, lineWidth: 0.75)
                    )
            )
        }
        .padding(12)
        .frame(height: rowHeight)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .onAppear { viewModel.refreshScriptLanguageDetection() }
        .onChange(of: viewModel.scriptText) { _, _ in
            viewModel.refreshScriptLanguageDetection()
        }
    }

    private func importOriginalText() {
        FilePickerHelper.pickFile(allowedTypes: [.plainText]) { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            viewModel.scriptText = text
        }
    }

    private var logSection: some View {
        LogConsoleView(
            runner: viewModel.runner,
            compactLines: 3,
            expandedLines: 12,
            startsExpanded: false,
            pinsToBottom: true,
            dockStyle: true,
            storageKey: "msm.logConsoleExpanded.script"
        )
    }
}
