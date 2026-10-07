import AppKit
import SwiftUI

struct SubtitleTranscriptEditorHost: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @State private var isPreviewPlaying = false
    @State private var playbackTime: Double?

    var body: some View {
        SubtitleTranscriptEditor(
            segments: viewModel.segments,
            playbackTime: playbackTime,
            isPlaying: isPreviewPlaying,
            srtURL: viewModel.srtURL,
            canUndo: viewModel.canUndoEdit,
            canRedo: viewModel.canRedoEdit,
            canSwitchVariant: viewModel.canSwitchTranscriptVariant,
            variantViewingLabel: viewModel.transcriptViewingLabel,
            variantToggleHint: viewModel.transcriptVariantToggleHint,
            onToggleVariant: { viewModel.toggleTranscriptVariant() },
            onSeek: { viewModel.seekToSegment($0, playAfter: false, forEditPreview: true) },
            onUpdateText: { viewModel.updateSegmentText(id: $0, text: $1) },
            onLiveEditText: { viewModel.setLiveEditDraft(id: $0, text: $1) },
            onLiveEditEnd: { viewModel.clearLiveEditDraft() },
            onMerge: { viewModel.mergeSegments(ids: $0) },
            onSplit: { viewModel.splitSegment(id: $0) },
            onDelete: { viewModel.deleteSegment(id: $0) },
            onUndo: { viewModel.undoEdit() },
            onRedo: { viewModel.redoEdit() },
            onCopy: { viewModel.copyTranscript() },
            onExportTXT: { viewModel.exportTXT() },
            onExportSRT: { viewModel.exportSRTToMediaFolder() },
            onExportXML: { viewModel.exportFCPXML() },
            onRevealFolder: { viewModel.revealExportBundleInFinder() },
            exportDeliverySignal: viewModel.exportDeliverySignal,
            translateAccessory: AnyView(
                HStack(spacing: 8) {
                    if viewModel.whisperComplete && viewModel.canRunWhisper {
                        AppPillButton(
                            title: "Tạo lại",
                            icon: "arrow.clockwise",
                            tint: AppTheme.accentBlue,
                            filled: false,
                            disabled: viewModel.isRunningWhisper
                        ) {
                            viewModel.runWhisper()
                        }
                    }
                    SubtitleTranslateMenuButton(viewModel: viewModel)
                }
            )
        )
        .background {
            TranscriptPlaybackObserver(
                isPlaying: $isPreviewPlaying,
                playbackTime: $playbackTime
            )
        }
    }
}

/// Giữ một editor duy nhất khi Phát/Dừng. Chỉ đẩy currentTime lúc đang phát.
/// Trước đây đổi hẳn Paused/Playing view làm NSTextView bị dismantle và commit như một lần lưu SRT.
private struct TranscriptPlaybackObserver: View {
    @Binding var isPlaying: Bool
    @Binding var playbackTime: Double?
    @ObservedObject private var preview = AVPreviewService.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { syncPlaybackState() }
            .onChange(of: preview.isPlaying) { syncPlaybackState() }
            .onChange(of: preview.currentTime) {
                guard preview.isPlaying else { return }
                playbackTime = preview.currentTime
            }
    }

    private func syncPlaybackState() {
        isPlaying = preview.isPlaying
        playbackTime = preview.isPlaying ? preview.currentTime : nil
    }
}

struct SubtitleTranscriptEditor: View {
    let segments: [SRTSegment]
    let playbackTime: Double?
    let isPlaying: Bool
    let srtURL: URL?
    let canUndo: Bool
    let canRedo: Bool
    let canSwitchVariant: Bool
    let variantViewingLabel: String
    let variantToggleHint: String
    let onToggleVariant: () -> Void
    let onSeek: (SRTSegment) -> Void
    let onUpdateText: (Int, String) -> Void
    var onLiveEditText: ((Int, String) -> Void)?
    var onLiveEditEnd: (() -> Void)?
    let onMerge: (Set<Int>) -> Bool
    let onSplit: (Int) -> Bool
    let onDelete: (Int) -> Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onExportTXT: () -> Void
    let onExportSRT: () -> Void
    var onExportXML: (() -> Void)? = nil
    var onRevealFolder: (() -> Void)? = nil
    var exportDeliverySignal: ExportDeliverySignal? = nil
    var translateAccessory: AnyView = AnyView(EmptyView())

    @State private var folderHighlighted = false
    @State private var toolbarFrames: [TranscriptToolbarSlot: CGRect] = [:]
    @State private var selectedIDs: Set<Int> = []
    @State private var editingID: Int?
    @State private var selectionAnchorID: Int?
    @State private var lastPlaybackScrollID: Int?
    @State private var seekTask: Task<Void, Never>?
    @FocusState private var keyboardFocused: Bool

    /// Debounce rất nhẹ (chỉ khi bấm liên tục) — tránh cảm giác trễ khi chọn dòng.
    private static let seekDebounceNs: UInt64 = 12_000_000

    private var playbackActiveID: Int? {
        guard isPlaying, let playbackTime else { return nil }
        return segments.segmentID(at: playbackTime)
    }

    private var primarySelectedID: Int? {
        selectedIDs.sorted().first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(segments) { segment in
                            row(for: segment)
                                .id(segment.id)

                            if segment.id != segments.last?.id {
                                Divider().opacity(0.2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: playbackActiveID) {
                    guard isPlaying, let newID = playbackActiveID, newID != lastPlaybackScrollID else { return }
                    lastPlaybackScrollID = newID
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .overlay {
            TranscriptExportFlyOverlay(
                signal: exportDeliverySignal,
                toolbarFrames: toolbarFrames,
                folderHighlighted: $folderHighlighted
            )
        }
        .onPreferenceChange(TranscriptToolbarFramesKey.self) { frames in
            toolbarFrames = frames
        }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onAppear {
            if editingID == nil { keyboardFocused = true }
        }
        .onChange(of: editingID) { _, newID in
            keyboardFocused = newID == nil
        }
        .background(shortcutButtons)
        .onKeyPress(.upArrow) {
            guard editingID == nil else { return .ignored }
            navigateSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard editingID == nil else { return .ignored }
            navigateSelection(by: 1)
            return .handled
        }
        .onKeyPress(.delete) {
            handleDeleteKey()
        }
    }

    private func row(for segment: SRTSegment) -> some View {
        let menuSelection = contextSelection(for: segment)
        return SubtitleSegmentRow(
            segment: segment,
            isPlaybackActive: playbackActiveID == segment.id,
            isSelected: selectedIDs.contains(segment.id),
            isEditing: editingID == segment.id,
            onRowTap: { handleRowTap(segment) },
            onRowDoubleTap: { beginEdit(segment) },
            onEditCommit: { text in commitEdit(for: segment.id, text: text) },
            onEditCancel: { cancelEdit() },
            onEditLiveChange: { text in onLiveEditText?(segment.id, text) },
            onContextSplit: { splitSelection(menuSelection) },
            onContextMerge: { mergeSelection(menuSelection) },
            onContextDelete: { deleteSelection(menuSelection) },
            canSplit: canSplit(menuSelection),
            canMerge: canMerge(menuSelection),
            canDelete: menuSelection.count == 1
        )
        .equatable()
    }

    private var shortcutButtons: some View {
        Group {
            Button("") { onUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canUndo)
            Button("") { onRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canRedo)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            if canSwitchVariant {
                SubtitleVariantSwitcher(
                    label: variantViewingLabel,
                    hint: variantToggleHint,
                    action: onToggleVariant
                )
            }

            translateAccessory

            Spacer(minLength: 8)

            SubtitleEditGuideButton()
            AppPillButton(title: "Sao chép", icon: "doc.on.doc", tint: AppTheme.accentBlue, filled: false, action: onCopy)
            AppPillButton(title: "TXT", icon: "doc.text", tint: AppTheme.accentBlue, filled: false, action: onExportTXT)
                .transcriptExportToolbarSlot(.txt)
            AppPillButton(title: "SRT", icon: "captions.bubble", tint: AppTheme.accentBlue, filled: false, action: onExportSRT)
                .transcriptExportToolbarSlot(.srt)
            if let onExportXML {
                AppPillButton(title: "XML", icon: "film", tint: AppTheme.accentBlue, filled: false, action: onExportXML)
                    .transcriptExportToolbarSlot(.xml)
            }
            if let onRevealFolder {
                AppPillButton(
                    title: "Thư mục",
                    icon: "folder",
                    tint: AppTheme.accentBlue,
                    filled: false,
                    highlighted: folderHighlighted,
                    action: onRevealFolder
                )
                .transcriptExportFolderSlot()
            } else if let srtURL {
                AppPillButton(
                    title: "Thư mục",
                    icon: "folder",
                    tint: AppTheme.accentBlue,
                    filled: false,
                    highlighted: folderHighlighted
                ) {
                    SRTExportService.revealInFinder(srtURL)
                }
                .transcriptExportFolderSlot()
            }
        }
        .coordinateSpace(name: "transcriptExportToolbar")
    }

    private func handleRowTap(_ segment: SRTSegment) {
        if NSEvent.modifierFlags.contains(.shift) {
            closeEditorAndSave()
            let anchor = selectionAnchorID ?? selectedIDs.first ?? segment.id
            selectionAnchorID = anchor
            selectRange(from: anchor, to: segment.id)
            keyboardFocused = true
            return
        }

        if editingID != nil, editingID != segment.id {
            closeEditorAndSave()
        }

        selectSingle(segment.id)
        // Seek ngay — không chờ debounce (cảm giác mượt khi bấm dòng).
        onSeek(segment)
        keyboardFocused = true
    }

    private func scheduleSeek(_ segment: SRTSegment) {
        // Chỉ dùng khi gõ ↑↓ liên tục — gộp nhẹ để đỡ spam seek.
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(nanoseconds: Self.seekDebounceNs)
            guard !Task.isCancelled else { return }
            onSeek(segment)
        }
    }

    private func handleDeleteKey() -> KeyPress.Result {
        guard editingID == nil, let id = primarySelectedID, selectedIDs.count == 1 else {
            return .ignored
        }
        if onDelete(id) {
            selectedIDs = []
            selectionAnchorID = nil
        }
        return .handled
    }

    private func navigateSelection(by delta: Int) {
        closeEditorAndSave()
        guard !segments.isEmpty, editingID == nil else { return }

        let currentID = primarySelectedID ?? playbackActiveID ?? segments.first?.id
        guard let currentID,
              let idx = segments.firstIndex(where: { $0.id == currentID }) else {
            if let first = segments.first {
                selectSingle(first.id)
                scheduleSeek(first)
            }
            return
        }

        let nextIdx = min(max(idx + delta, 0), segments.count - 1)
        let next = segments[nextIdx]
        selectSingle(next.id)
        scheduleSeek(next)
    }

    private func contextSelection(for segment: SRTSegment) -> Set<Int> {
        if selectedIDs.contains(segment.id), !selectedIDs.isEmpty {
            return selectedIDs
        }
        return [segment.id]
    }

    private func canSplit(_ ids: Set<Int>) -> Bool {
        ids.count == 1
    }

    private func canMerge(_ ids: Set<Int>) -> Bool {
        guard ids.count == 2 else { return false }
        let selected = segments.filter { ids.contains($0.id) }.sorted { $0.index < $1.index }
        guard selected.count == 2,
              let firstIdx = segments.firstIndex(where: { $0.id == selected[0].id }),
              let secondIdx = segments.firstIndex(where: { $0.id == selected[1].id }) else {
            return false
        }
        return secondIdx == firstIdx + 1
    }

    private func beginEdit(_ segment: SRTSegment) {
        if editingID != nil, editingID != segment.id {
            closeEditorAndSave()
        }
        selectSingle(segment.id)
        scheduleSeek(segment)
        editingID = segment.id
    }

    /// Đóng editor → dismantle NSTextView → tự commit qua `dismantleNSView`.
    private func closeEditorAndSave() {
        guard editingID != nil else { return }
        editingID = nil
        keyboardFocused = true
    }

    private func commitEdit(for id: Int, text: String) {
        onUpdateText(id, text)
        onLiveEditEnd?()
        if editingID == id {
            editingID = nil
        }
        keyboardFocused = true
    }

    private func cancelEdit() {
        onLiveEditEnd?()
        editingID = nil
        keyboardFocused = true
    }

    private func selectSingle(_ id: Int) {
        selectedIDs = [id]
        selectionAnchorID = id
    }

    private func selectRange(from anchorID: Int, to currentID: Int) {
        guard let anchorIdx = segments.firstIndex(where: { $0.id == anchorID }),
              let currentIdx = segments.firstIndex(where: { $0.id == currentID }) else {
            return
        }
        let lower = min(anchorIdx, currentIdx)
        let upper = max(anchorIdx, currentIdx)
        selectedIDs = Set(segments[lower...upper].map(\.id))
    }

    private func splitSelection(_ ids: Set<Int>) {
        closeEditorAndSave()
        guard let id = ids.first, ids.count == 1 else { return }
        selectSingle(id)
        if onSplit(id) {
            selectedIDs = []
            selectionAnchorID = nil
        }
    }

    private func mergeSelection(_ ids: Set<Int>) {
        closeEditorAndSave()
        guard canMerge(ids) else { return }
        if onMerge(ids) {
            selectedIDs = []
            selectionAnchorID = nil
        }
    }

    private func deleteSelection(_ ids: Set<Int>) {
        closeEditorAndSave()
        guard let id = ids.first, ids.count == 1 else { return }
        if onDelete(id) {
            selectedIDs = []
            selectionAnchorID = nil
        }
    }
}
