import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Workspace chính của app: toàn bộ thao tác subtitle đi qua timeline này.
struct SubtitleTimelineWorkspace: View {
    private enum RightPanelMode { case cues, style, dubbing }
    private enum TimelineSelectionFocus { case subtitle, dubbing }
    private struct SnapEdge: Equatable {
        let cueID: Int
        let time: Double
    }
    private struct CueRevealRequest: Equatable {
        let cueID: Int
        let token: UUID
    }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject private var preview = AVPreviewService.shared
    @ObservedObject private var dubbingSession = DubbingSessionModel.shared
    @State private var cueSelection = TimelineCueSelection()
    @State private var dubbingSelection = TimelineCueSelection()
    @State private var timelineSelectionFocus: TimelineSelectionFocus = .subtitle
    @State private var editingCueID: Int?
    @AppStorage("msm.workspace.importVisible") private var isImportVisible = true
    @State private var isImportDropTarget = false
    @State private var rightPanelMode: RightPanelMode = .cues
    @State private var pixelsPerSecond = 72.0
    @State private var viewportWidth: CGFloat = 900
    @State private var timelineScrollView: NSScrollView?
    @State private var peaks: [Float] = []
    @State private var waveformDuration = 0.0
    @State private var waveformContentID = UUID()
    @State private var skimming = true
    @State private var snapEnabled = true
    @State private var clickMarkerTime: Double?
    @State private var timelineDragStartX: CGFloat?
    /// Chỉ reveal cue khi người dùng chọn từ danh sách bên; token bảo đảm bấm
    /// lại chính cue đang chọn vẫn cuộn tới đầu cue. Click tile không tự cuộn.
    @State private var cueRevealRequest: CueRevealRequest?
    /// Chiều ngược lại chỉ cuộn danh sách Cue bên phải. Tách request để click
    /// tile không kích hoạt reveal Timeline và tái hiện lỗi tự nhảy viewport.
    @State private var cuePanelRevealRequest: CueRevealRequest?
    @State private var playheadDragStartTime: Double?
    @State private var playheadDragTime: Double?
    /// Playhead đỏ chỉ xuất hiện sau một hành động chốt (click nền/Space/kéo nó).
    @State private var hasCommittedPlayhead = false
    /// Skimmer chỉ là vị trí hover tạm dưới con trỏ; không được làm playhead đỏ nhảy theo.
    @State private var skimTime: Double?
    /// Đường Skim và preview luôn dùng cùng một time. Snap tắt = raw dưới chuột;
    /// Snap bật = cả hai cùng dính playhead hoặc đầu/đuôi cue gần nhất.
    @State private var skimDisplayTime: Double?
    @State private var skimViewportX: CGFloat?
    @State private var isScriptSheetOpen = false
    @State private var isStyleSheetOpen = false
    @State private var isShortcutSheetOpen = false
    @State private var exportDeliveryToast: ExportDeliverySignal?
    @State private var qualityIssues: [SubtitleQualityIssue] = []
    @State private var cueSnapEdges: [SnapEdge] = []
    @State private var qualityRefreshTask: Task<Void, Never>?
    @State private var keyMonitor: Any?

    private var duration: Double {
        let rawCueDuration = viewModel.segments.map(\.endSeconds).max() ?? 0
        let cueDuration = rawCueDuration.isFinite && rawCueDuration > 0 ? rawCueDuration : 0
        let previewDuration = preview.duration.isFinite && preview.duration > 0 ? preview.duration : 0
        let decodedWaveformDuration = waveformDuration.isFinite && waveformDuration > 0 ? waveformDuration : 0

        func includingReasonableCueTail(_ mediaDuration: Double) -> Double {
            guard mediaDuration > 0 else { return cueDuration }
            // SRT có thể dài hơn media vài giây, nhưng một timestamp hỏng không được
            // kéo overview thành hàng giờ/ngày rồi làm toàn bộ Timeline biến mất.
            let allowedTail = max(5, mediaDuration * 0.25)
            guard cueDuration <= mediaDuration + allowedTail else { return mediaDuration }
            return max(mediaDuration, cueDuration)
        }

        // AAC/M4A có track timescale lỗi có thể khiến AVPlayerItem báo duration 2×.
        // Với audio thuần, waveform đã xác minh bằng PCM frame/rate là nguồn đúng;
        // video vẫn lấy duration preview để không cắt đoạn hình không có audio.
        if isAudioOnlyMedia, decodedWaveformDuration > 0 {
            return max(includingReasonableCueTail(decodedWaveformDuration), 1)
        }
        if previewDuration > 0 {
            return max(includingReasonableCueTail(previewDuration), 1)
        }
        if decodedWaveformDuration > 0 {
            return max(includingReasonableCueTail(decodedWaveformDuration), 1)
        }
        return max(cueDuration, 1)
    }
    private var timelineWidth: CGFloat {
        let width = duration * pixelsPerSecond
        guard width.isFinite, width > 0 else { return max(1, viewportWidth) }
        return CGFloat(width)
    }
    private var selectedID: Int? { cueSelection.primaryID }
    private var selectedIDs: Set<Int> { cueSelection.selectedIDs }
    private var selectedDubbingIDs: Set<Int> { dubbingSelection.selectedIDs }
    private var selectedCue: SRTSegment? { viewModel.segments.first { $0.id == selectedID } }
    /// Khi Skim đang hiển thị frame tạm, subtitle preview cũng phải đi theo frame
    /// đó; `AVPlayer.currentTime` cố ý vẫn giữ playhead đỏ nên không dùng trực tiếp.
    private var displayedPreviewTime: Double {
        if isSkimmingActive, !preview.isPlaying, let skimTime { return skimTime }
        return preview.currentTime
    }
    private var selectedIndices: [Int] {
        cueSelection.selectedIndices(orderedIDs: viewModel.segments.map(\.id))
    }
    private var canMergeSelectedCues: Bool {
        timelineSelectionFocus == .subtitle
            && cueSelection.canMerge(orderedIDs: viewModel.segments.map(\.id))
    }
    private var canDeleteSelectedCues: Bool {
        timelineSelectionFocus == .subtitle
            && cueSelection.canDelete(totalCueCount: viewModel.segments.count)
    }
    private var canDeleteTimelineSelection: Bool {
        timelineSelectionFocus == .dubbing ? !selectedDubbingIDs.isEmpty : canDeleteSelectedCues
    }
    private var canRenderSelectedDubbing: Bool {
        AppFeatureFlags.dubbingEnabled && DubbingToolbarAvailability.canRenderSelected(
            hasSubtitleSelection: timelineSelectionFocus == .subtitle && !selectedIDs.isEmpty,
            providerReady: dubbingSession.selectedProviderReady,
            isRendering: dubbingSession.isRendering
        )
    }
    private var canRenderAllDubbing: Bool {
        AppFeatureFlags.dubbingEnabled && DubbingToolbarAvailability.canRenderAll(
            hasCues: !viewModel.segments.isEmpty,
            providerReady: dubbingSession.selectedProviderReady,
            isRendering: dubbingSession.isRendering
        )
    }
    private var isDubbingErrorPresented: Binding<Bool> {
        Binding(
            get: { dubbingSession.errorMessage != nil },
            set: { isPresented in
                if !isPresented { dubbingSession.errorMessage = nil }
            }
        )
    }
    /// Xóa trái/phải lấy skimmer khi có; ngoài ra dùng playhead đỏ đã chốt.
    private var sideDeleteReferenceTime: Double { isSkimmingActive ? (skimTime ?? preview.currentTime) : preview.currentTime }
    private var canDeleteSelectedCueSide: Bool {
        guard timelineSelectionFocus == .subtitle,
              selectedIDs.count == 1,
              let cue = selectedCue else { return false }
        let minimumDuration = 0.05
        return sideDeleteReferenceTime > cue.startSeconds + minimumDuration
            && sideDeleteReferenceTime < cue.endSeconds - minimumDuration
    }

    private var isAudioOnlyMedia: Bool {
        guard let extensionType = viewModel.mediaURL.flatMap({ UTType(filenameExtension: $0.pathExtension) }) else {
            return false
        }
        return extensionType.conforms(to: .audio) && !extensionType.conforms(to: .movie)
    }
    /// Skim là thao tác xem trước khi pause; playback đã có playhead native riêng.
    private var isSkimmingActive: Bool { skimming && !preview.isPlaying }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            VSplitView {
                HSplitView {
                    if isImportVisible {
                        sourcePanel.frame(minWidth: 250, idealWidth: 300)
                    }
                    previewPanel.frame(minWidth: 420, maxWidth: .infinity)
                    inspectorPanel.frame(minWidth: 300, idealWidth: 350)
                }
                .frame(minHeight: 280, idealHeight: 390)
                .background(
                    PersistentSplitViewAutosave(
                        name: isImportVisible
                            ? "MediaSupportMaster.Workspace.Horizontal.WithImport.v2"
                            : "MediaSupportMaster.Workspace.Horizontal.Compact.v2",
                        splitIsVertical: true
                    )
                    .frame(width: 1, height: 1)
                )
                VStack(spacing: 0) { controlStrip; timelinePanel }
                    .frame(minHeight: 270)
            }
            .background(
                PersistentSplitViewAutosave(
                    name: "MediaSupportMaster.Workspace.Vertical.v2",
                    splitIsVertical: false
                )
                    .frame(width: 1, height: 1)
            )
        }
        .padding(0)
        .frame(minWidth: 1040, minHeight: 720)
        .overlay(alignment: .bottomTrailing) {
            if let exportDeliveryToast {
                TimelineExportDeliveryToast(
                    signal: exportDeliveryToast,
                    onReveal: viewModel.revealExportDeliverableInFinder,
                    onDismiss: { withAnimation(.easeOut(duration: 0.18)) { self.exportDeliveryToast = nil } }
                )
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            installShortcuts()
            reloadWaveform()
            refreshSubtitleQuality()
            refreshCueSnapEdges()
            synchronizeDubbingIfEnabled()
            synchronizeDubbingPreview()
        }
        .onDisappear {
            removeShortcuts()
            qualityRefreshTask?.cancel()
            dubbingSession.synchronizePreviewPlayback(at: preview.currentTime, isPlaying: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTimelineShortcutSettings)) { _ in
            isShortcutSheetOpen = true
        }
        .onChange(of: viewModel.mediaURL) { _, _ in
            hasCommittedPlayhead = false
            reloadWaveform()
            scheduleSubtitleQualityRefresh()
            synchronizeDubbingIfEnabled()
        }
        .onChange(of: viewModel.segments) { _, _ in
            scheduleSubtitleQualityRefresh()
            refreshCueSnapEdges()
            synchronizeDubbingIfEnabled()
        }
        .onChange(of: viewModel.burnStyle) { _, _ in scheduleSubtitleQualityRefresh() }
        .onChange(of: viewModel.wrapStyle) { _, _ in scheduleSubtitleQualityRefresh() }
        .onChange(of: preview.isPlaying) { _, isPlaying in
            if isPlaying {
                skimTime = nil
                skimDisplayTime = nil
            }
            synchronizeDubbingPreview()
        }
        .onChange(of: preview.currentTime) { _, _ in synchronizeDubbingPreview() }
        .onChange(of: dubbingSession.renderedByCueID) { _, _ in
            dubbingSelection.reconcile(orderedIDs: dubbingSession.effectiveRenderedCues.map(\.id))
            synchronizeDubbingPreview()
        }
        .onChange(of: dubbingSession.playbackRateByFingerprint) { _, _ in
            // Kéo handle cập nhật lane theo thời gian thực nhưng không restart
            // AVPlayer liên tục; khi mouse-up session sẽ sync đúng rate một lần.
            guard NSEvent.pressedMouseButtons == 0 else { return }
            synchronizeDubbingPreview()
        }
        .onChange(of: dubbingSession.originalVolume) { _, _ in synchronizeDubbingPreview() }
        .onChange(of: dubbingSession.dubVolume) { _, _ in synchronizeDubbingPreview() }
        .onChange(of: dubbingSession.duckOriginal) { _, _ in synchronizeDubbingPreview() }
        .onChange(of: viewModel.segments.map(\.id)) { _, ids in cueSelection.reconcile(orderedIDs: ids) }
        .onChange(of: viewModel.exportDeliverySignal?.token) { _, _ in
            guard let signal = viewModel.exportDeliverySignal else { return }
            withAnimation(.spring(duration: 0.28)) { exportDeliveryToast = signal }
            let token = signal.token
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard exportDeliveryToast?.token == token else { return }
                    withAnimation(.easeOut(duration: 0.2)) { exportDeliveryToast = nil }
                }
            }
        }
        .sheet(isPresented: $isScriptSheetOpen) { SubtitleScriptComposer(viewModel: viewModel) }
        .sheet(isPresented: $isStyleSheetOpen) { SubtitleTimelineStyleSheet(viewModel: viewModel) }
        .sheet(isPresented: $isShortcutSheetOpen) { TimelineShortcutSettingsSheet() }
    }

    private var workspaceHeader: some View {
        WindowDragHandle()
        .frame(height: 20)
        .background(AppTheme.inputFill.opacity(0.82))
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
        }
        .alert("Không thể hoàn tất tác vụ", isPresented: isDubbingErrorPresented) {
            Button("Đã hiểu") { dubbingSession.errorMessage = nil }
        } message: {
            Text(dubbingSession.errorMessage ?? "")
        }
    }

    private var sourcePanel: some View {
        TimelineSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Media & phụ đề")
                        .font(AppFont.label)
                        .foregroundStyle(AppTheme.headlineText)
                    Spacer()
                    Button { isImportVisible = false } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                            .frame(width: 28, height: AppTheme.compactControlHeight)
                    }
                        .buttonStyle(TimelineToolbarButtonStyle())
                        .help("Ẩn Import")
                        .accessibilityLabel("Ẩn Import")
                    Button(action: closeProject) {
                        Image(systemName: "trash")
                            .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                            .frame(width: 28, height: AppTheme.compactControlHeight)
                    }
                        .buttonStyle(TimelineToolbarButtonStyle())
                        .disabled(viewModel.mediaURL == nil && viewModel.srtURL == nil)
                        .help("Xóa dự án khỏi ứng dụng")
                        .accessibilityLabel("Xóa dự án khỏi ứng dụng")
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
                }
                projectBrowser
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isImportDropTarget) { providers in
            handleImportDrop(providers)
        }
        .overlay {
            if isImportDropTarget {
                RoundedRectangle(cornerRadius: 0)
                    .fill(AppTheme.accentBlue.opacity(0.16))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Thả để nhập media hoặc SRT")
                                .font(AppFont.label)
                        }
                        .foregroundStyle(AppTheme.accentBlue)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var projectBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileRow(viewModel.mediaURL, icon: "film.stack", remove: removeMedia)
            fileRow(viewModel.srtURL, icon: "captions.bubble", remove: removeSRT)
            if viewModel.mediaURL == nil && viewModel.srtURL == nil {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                    Text("Kéo thả media hoặc SRT vào đây")
                        .font(AppFont.label)
                    Text("Video · Audio · Phụ đề SRT")
                        .font(AppFont.editorLabel)
                }
                .foregroundStyle(AppTheme.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.editorFieldRadius, style: .continuous)
                        .stroke(
                            AppTheme.mutedText.opacity(0.42),
                            style: StrokeStyle(lineWidth: 0.75, dash: [5, 5])
                        )
                }
                .opacity(0.70)
                .padding(.horizontal, 18)
                .allowsHitTesting(false)
                Spacer()
            } else {
                Spacer()
            }
        }
    }

    @ViewBuilder private func fileRow(_ url: URL?, icon: String, remove: @escaping () -> Void) -> some View {
        if let url {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.compactIconSize, weight: .medium))
                    .foregroundStyle(AppTheme.accentBlue)
                    .frame(width: 16)
                Text(url.lastPathComponent)
                    .font(AppFont.editorBodyStrong)
                    .foregroundStyle(AppTheme.bodyText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(TimelineToolbarButtonStyle())
                .foregroundStyle(AppTheme.mutedText)
                .help("Bỏ \(url.lastPathComponent)")
                .accessibilityLabel("Bỏ \(url.lastPathComponent)")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.divider.opacity(0.55)).frame(height: AppTheme.hairlineWidth)
            }
        }
    }
    private var previewPanel: some View {
        // AVPlayerView giữ video theo .resizeAspect trong vùng đen. Overlay phải dùng
        // cùng hình chữ nhật video (không phải toàn bộ panel), để font/lề/bố cục luôn
        // đúng canvas 16:9 khi người dùng đổi kích thước cửa sổ.
        let videoDisplaySize = preview.currentURL.map { VideoGeometryProbe.displaySize(for: $0) }
            ?? CGSize(width: 1920, height: 1080)
        let videoAspect = max(0.01, videoDisplaySize.width / max(videoDisplaySize.height, 1))
        let referencePixelHeight = VideoPreviewFrame.classify(displaySize: videoDisplaySize)
            .referencePixelSize.height

        return TimelineSurface(padding: 8) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black.opacity(0.88)
                    if let player = preview.player { AVPlayerContainerView(player: player, showsBuiltInControls: false) }
                    if preview.isLoaded,
                       let overlay = SubtitlePreviewOverlayView.make(
                           segments: viewModel.segments,
                           currentTime: displayedPreviewTime,
                           style: viewModel.burnStyle,
                           isPlaying: preview.isPlaying,
                           videoAspectRatio: videoAspect,
                           referencePixelHeight: referencePixelHeight
                       ) {
                        overlay
                    } else if !preview.isLoaded {
                        ContentUnavailableView("Timeline subtitle", systemImage: "captions.bubble", description: Text("Mở media hoặc SRT ở cột trái."))
                    }
                    if viewModel.isRunningWhisper {
                        PreviewJobProgressOverlay(percent: viewModel.whisperProgressPercent)
                            .accessibilityLabel(L10n.format("Chép lời %@ phần trăm", String(viewModel.whisperProgressPercent)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if preview.isLoaded || !viewModel.segments.isEmpty {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        compactButton(preview.isPlaying ? "pause.fill" : "play.fill", help: preview.isPlaying ? "Tạm dừng" : "Phát") { togglePlaybackFromPointer() }
                        Text(timecode(preview.currentTime))
                            .font(AppFont.previewTimecode)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.mutedText)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 36)
                    .background(AppTheme.tileFill)
                }
            }
            .overlay(alignment: .topLeading) {
                if !isImportVisible {
                    Button { isImportVisible = true } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                            .frame(width: 30, height: AppTheme.compactControlHeight)
                    }
                    .buttonStyle(TimelineToolbarButtonStyle())
                    .foregroundStyle(.white)
                    .padding(8)
                    .help("Hiện Import")
                    .accessibilityLabel("Hiện Import")
                }
            }
        }
    }
    private func compactButton(_ icon: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon)
                .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                .frame(width: 28, height: AppTheme.compactControlHeight)
        }
        .buttonStyle(TimelineToolbarButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var inspectorPanel: some View {
        TimelineSurface(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    inspectorModeButton(.cues, icon: "captions.bubble.fill", title: "Cue", help: "Cue và sửa nội dung")
                    inspectorModeButton(.style, icon: "character.textbox", title: "Kiểu sub", help: "Chỉnh kiểu phụ đề")
                    if AppFeatureFlags.dubbingEnabled {
                        inspectorModeButton(.dubbing, icon: "waveform.badge.mic", title: "Lồng tiếng", help: "Tạo và trộn giọng theo cue")
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(AppTheme.insetFill)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
                }
                if rightPanelMode == .cues {
                    cueEditorPanel
                } else if rightPanelMode == .style {
                    SubtitleBurnSlideContent(viewModel: viewModel, showsHeader: false, showsExportControls: false)
                } else if AppFeatureFlags.dubbingEnabled {
                    DubbingInspectorPanel(
                        session: .shared,
                        cues: viewModel.segments
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func inspectorModeButton(_ mode: RightPanelMode, icon: String, title: String, help: String) -> some View {
        Button { rightPanelMode = mode } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                Text(L10n.string(title)).font(AppFont.editorBodyStrong)
            }
                .frame(maxWidth: .infinity, minHeight: AppTheme.compactControlHeight)
                .foregroundStyle(rightPanelMode == mode ? .white : AppTheme.headlineText)
                .background(rightPanelMode == mode ? AppTheme.editorActiveFill : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(rightPanelMode == mode ? AppTheme.editorAccent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TimelineTabHoverHighlight())
        .help(L10n.string(help))
        .accessibilityLabel(L10n.string(title))
        .accessibilityValue(L10n.string(rightPanelMode == mode ? "Đang chọn" : "Chưa chọn"))
        .accessibilityAddTraits(rightPanelMode == mode ? .isSelected : [])
    }

    private var cueEditorPanel: some View {
        VStack(spacing: 0) {
            if viewModel.segments.isEmpty { ContentUnavailableView("Chưa có cue", systemImage: "captions.bubble", description: Text("Chép lời, tạo từ văn bản, hoặc nhập SRT.")) }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.segments) { cue in
                                cueRow(cue)
                                    .id(cuePanelAnchorID(cue.id))
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: cuePanelRevealRequest) { _, request in
                        guard let request,
                              viewModel.segments.contains(where: { $0.id == request.cueID })
                        else { return }
                        if reduceMotion {
                            proxy.scrollTo(cuePanelAnchorID(request.cueID), anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(cuePanelAnchorID(request.cueID), anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cuePanelAnchorID(_ id: Int) -> String { "cue-panel-\(id)" }
    @ViewBuilder private func cueRow(_ cue: SRTSegment) -> some View {
        if editingCueID == cue.id {
            SubtitleTimelineTextEditor(
                cue: cue,
                onSave: { viewModel.updateSegmentText(id: cue.id, text: $0) },
                onFinish: { editingCueID = nil }
            )
            .padding(9)
            .background(AppTheme.editorSelectionFill.opacity(0.34))
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.divider.opacity(0.55)).frame(height: AppTheme.hairlineWidth)
            }
            .accessibilityLabel(L10n.format("Đang sửa cue %@", cue.startLabel))
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text(cue.startLabel)
                    .font(AppFont.editorTimecode)
                    .monospacedDigit()
                    .foregroundStyle(selectedIDs.contains(cue.id) ? Color.white.opacity(0.92) : AppTheme.editorAccent)
                    .frame(width: 68, alignment: .leading)
                Text(cue.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(selectedIDs.contains(cue.id) ? AppFont.editorBodyStrong : AppFont.editorBody)
            .foregroundStyle(selectedIDs.contains(cue.id) ? .white : AppTheme.bodyText)
            .padding(9)
            .background(selectedIDs.contains(cue.id) ? AppTheme.editorSelectionFill : .clear)
            .contentShape(Rectangle())
            // Cue panel là nơi duy nhất mở editor: tránh Button + gesture cạnh tranh
            // khiến double-click bị nuốt. Timeline chỉ chọn/seek/drag/trim.
            .gesture(
                TapGesture(count: 2)
                    .onEnded { openCueTextEditor(cue) }
                    .exclusively(before: TapGesture()
                        .onEnded { selectCueFromPanel(cue, intent: .from(NSEvent.modifierFlags)) })
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cue \(cue.startLabel), \(cue.text.replacingOccurrences(of: "\n", with: " "))")
            .accessibilityHint("Bấm để chọn, bấm đúp để sửa nội dung")
            .accessibilityValue(selectedIDs.contains(cue.id) ? "Đang chọn" : "Chưa chọn")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selectedIDs.contains(cue.id) ? .isSelected : [])
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.divider.opacity(0.55)).frame(height: AppTheme.hairlineWidth)
            }
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 10)
            HStack(spacing: AppTheme.controlGap) {
                whisperToolButton
                timelineToolButton("doc.text", title: "Văn bản gốc", active: false, help: "Giữ nguyên chữ và khớp thời gian theo media") { beginScriptSubtitle() }
                    .disabled(viewModel.mediaURL == nil || viewModel.isRunningScriptAlign)
                SubtitleTranslateMenuButton(viewModel: viewModel)
                    .help("Dịch phụ đề")
                if AppFeatureFlags.dubbingEnabled {
                    timelineToolButton(
                        "waveform.badge.plus",
                        title: "Lồng cue chọn",
                        active: canRenderSelectedDubbing,
                        help: "Tạo giọng cho các cue phụ đề đang chọn"
                    ) {
                        rightPanelMode = .dubbing
                        dubbingSession.renderSelected(cues: viewModel.segments, selectedIDs: selectedIDs)
                    }
                    .disabled(!canRenderSelectedDubbing)
                    timelineToolButton(
                        "waveform.path",
                        title: dubbingSession.isRendering ? "Dừng" : "Lồng toàn bộ",
                        active: dubbingSession.isRendering,
                        help: dubbingSession.isRendering ? "Dừng tạo giọng" : "Tạo giọng cho toàn bộ phụ đề"
                    ) {
                        rightPanelMode = .dubbing
                        if dubbingSession.isRendering {
                            dubbingSession.cancelRendering()
                        } else {
                            dubbingSession.renderAll(cues: viewModel.segments)
                        }
                    }
                    .disabled(!dubbingSession.isRendering && !canRenderAllDubbing)
                }
                // QC mặc định chỉ xuất hiện khi có lỗi xác định chắc chắn.
                // Cue bình thường không còn bị một con số cảnh báo chủ quan gây rối.
                if !qualityIssues.isEmpty {
                    subtitleQualityMenu
                }
            }
            toolbarDivider
            HStack(spacing: AppTheme.controlGap) {
                Text("Zoom")
                    .font(AppFont.editorLabel)
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(height: 22, alignment: .center)
                TimelineZoomSlider(
                    value: Binding(
                        get: { pixelsPerSecond },
                        set: { applyTimelineZoom($0) }
                    ),
                    range: 0.01...260
                )
                    .frame(width: 86, height: 22)
                    .help("Kéo để phóng to / thu nhỏ Timeline")
                timelineToolButton("viewfinder", title: "Snap", active: snapEnabled, help: "Snap: Skim, playhead và cue bám đầu / đuôi cue") { snapEnabled.toggle() }
                timelineToolButton("cursorarrow.motionlines", title: "Skim", active: isSkimmingActive, help: preview.isPlaying ? "Skim tạm nghỉ khi preview đang phát" : "Skim: rê chuột trên Timeline để xem nhanh") { setSkimming(!skimming) }
                    .disabled(preview.isPlaying)
            }
            toolbarDivider
            HStack(spacing: AppTheme.controlGap) {
                timelineToolButton("arrow.uturn.backward", title: "Hoàn tác", active: false, help: "Hoàn tác") { viewModel.undoEdit() }.disabled(!viewModel.canUndoEdit)
                timelineToolButton("arrow.uturn.forward", title: "Làm lại", active: false, help: "Làm lại") { viewModel.redoEdit() }.disabled(!viewModel.canRedoEdit)
                timelineCueEditButton("arrow.left.to.line.compact", title: "Xóa trái", help: "Bỏ phần bên trái tại Skim hoặc playhead", width: 72) { deleteSelectedLeftSide() }.disabled(!canDeleteSelectedCueSide)
                timelineCueEditButton("arrow.right.to.line.compact", title: "Xóa phải", help: "Bỏ phần bên phải tại Skim hoặc playhead", width: 72) { deleteSelectedRightSide() }.disabled(!canDeleteSelectedCueSide)
                timelineCueEditButton("scissors", title: "Tách", help: "Tách cue đang chọn · X") { splitSelected() }
                    .disabled(timelineSelectionFocus != .subtitle || selectedIDs.count != 1)
                timelineCueEditButton("rectangle.stack.fill", title: "Gộp", help: "Gộp các cue liền kề đã chọn · G") { mergeSelected() }.disabled(!canMergeSelectedCues)
                timelineToolButton("trash", title: "Xóa", active: false, help: "Xóa mục Timeline đã chọn · Delete") { deleteSelected() }
                    .disabled(!canDeleteTimelineSelection)
            }
            toolbarDivider
            HStack(spacing: AppTheme.controlGap) {
                timelineToolButton("captions.bubble", title: "Xuất SRT", active: false, help: "Xuất SRT") { viewModel.exportSRTToMediaFolder() }
                    .disabled(viewModel.segments.isEmpty)
                timelineToolButton("doc.plaintext", title: "Xuất TXT", active: false, help: "Xuất TXT") { viewModel.exportTXT() }
                    .disabled(viewModel.segments.isEmpty)
                timelineToolButton("film.stack", title: "Xuất XML", active: false, help: "Xuất Final Cut XML") { viewModel.exportFCPXML() }
                    .disabled(viewModel.segments.isEmpty)
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(AppTheme.tileFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(width: AppTheme.hairlineWidth, height: 20)
            .padding(.horizontal, 1)
    }

    private var subtitleQualityMenu: some View {
        Menu {
            if qualityIssues.isEmpty {
                Text(viewModel.segments.isEmpty ? "Chưa có cue để kiểm tra" : "Không phát hiện lỗi")
            } else {
                ForEach(qualityIssues.prefix(30)) { issue in
                    Button {
                        focusQualityIssue(issue)
                    } label: {
                        Label(
                            "Cue \(issue.cueID) · \(issue.message)",
                            systemImage: issue.severity == .error ? "exclamationmark.octagon" : "exclamationmark.triangle"
                        )
                    }
                }
                if qualityIssues.count > 30 {
                    Divider()
                    Text(L10n.format("Còn %d cảnh báo", qualityIssues.count - 30))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: qualityIssues.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill")
                    .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                Text(qualityIssues.isEmpty ? "QC" : "QC \(qualityIssues.count)")
                    .font(AppFont.editorLabel)
            }
            .foregroundStyle(qualityIssues.isEmpty ? AppTheme.headlineText : qualityMenuTint)
            .padding(.horizontal, 9)
            .frame(minHeight: AppTheme.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .fill(qualityIssues.isEmpty ? AppTheme.controlFill : qualityMenuTint.opacity(0.13))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(qualityIssues.isEmpty
            ? L10n.string("Kiểm tra chất lượng subtitle")
            : L10n.format("Có %d vấn đề cần xem", qualityIssues.count))
        .accessibilityLabel(qualityIssues.isEmpty
            ? L10n.string("QC subtitle, không có lỗi")
            : L10n.format("QC subtitle, %d vấn đề", qualityIssues.count))
    }

    private var qualityMenuTint: Color {
        qualityIssues.contains(where: { $0.severity == .error }) ? AppTheme.accentRed : AppTheme.accentOrange
    }

    private func refreshSubtitleQuality() {
        let detected = SubtitleQualityAnalyzer.analyze(
            viewModel.segments,
            configuration: viewModel.subtitleLayoutConfiguration(explicitBreakPolicy: .preserve)
        )
        // CPS, thời lượng và phép đo tràn phụ thuộc nội dung/phông/video nên chỉ
        // là gợi ý. Toolbar chỉ báo ba lỗi có kết luận khách quan, tránh false positive.
        qualityIssues = detected.filter {
            switch $0.code {
            case .emptyText, .tooManyLines, .overlap:
                return true
            case .lineOverflow, .tooFast, .tooShort, .tooLong:
                return false
            }
        }
    }

    private func scheduleSubtitleQualityRefresh() {
        qualityRefreshTask?.cancel()
        let segments = viewModel.segments
        let configuration = viewModel.subtitleLayoutConfiguration(explicitBreakPolicy: .preserve)
        qualityRefreshTask = Task { @MainActor in
            // Slider font/box phát nhiều event; chỉ đo glyph sau nhịp chỉnh cuối.
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            let detected = await Task.detached(priority: .utility) {
                SubtitleQualityAnalyzer.analyze(
                    segments,
                    configuration: configuration
                )
            }.value
            guard !Task.isCancelled else { return }
            // CPS, thời lượng và phép đo tràn là gợi ý; toolbar chỉ đưa các lỗi
            // khách quan lên trước để tránh cảnh báo giả khi người dùng kéo style.
            qualityIssues = detected.filter {
                switch $0.code {
                case .emptyText, .tooManyLines, .overlap:
                    return true
                case .lineOverflow, .tooFast, .tooShort, .tooLong:
                    return false
                }
            }
        }
    }

    private func focusQualityIssue(_ issue: SubtitleQualityIssue) {
        guard let cue = viewModel.segments.first(where: { $0.id == issue.cueID }) else { return }
        rightPanelMode = .cues
        selectCueFromPanel(cue, intent: .replace)
    }

    private var whisperToolButton: some View {
        Button(action: beginWhisper) {
            HStack(spacing: 5) {
                Image(systemName: viewModel.isRunningWhisper ? "waveform.badge.mic" : "waveform.badge.mic")
                    .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: viewModel.isRunningWhisper && !reduceMotion)
                Text("Chép lời")
                    .font(AppFont.editorLabel)
                if viewModel.isRunningWhisper {
                    Text("\(viewModel.whisperProgressPercent)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(viewModel.isRunningWhisper ? .white : AppTheme.headlineText)
            .padding(.horizontal, 9)
            .frame(minHeight: AppTheme.compactControlHeight)
        }
        .buttonStyle(TimelineToolbarButtonStyle(isActive: viewModel.isRunningWhisper))
        .disabled(viewModel.mediaURL == nil || viewModel.isRunningWhisper)
        .help(viewModel.isRunningWhisper ? "Đang chép lời: \(viewModel.whisperProgressPercent)%" : "Chép lời từ media")
        .accessibilityLabel(viewModel.isRunningWhisper ? "Đang chép lời \(viewModel.whisperProgressPercent) phần trăm" : "Chép lời từ media")
    }

    private func timelineToolButton(
        _ icon: String,
        title: String? = nil,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                if let title {
                    Text(L10n.string(title))
                        .font(AppFont.editorLabel)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(active ? .white : AppTheme.headlineText)
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(minWidth: 30, minHeight: AppTheme.compactControlHeight, maxHeight: AppTheme.compactControlHeight)
        }
        .buttonStyle(TimelineToolbarButtonStyle(isActive: active))
        .help(L10n.string(help))
        .accessibilityLabel(L10n.string(title ?? help))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func timelineCueEditButton(_ icon: String, title: String, help: String, width: CGFloat = 58, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.compactIconSize, weight: .semibold))
                Text(L10n.string(title))
                    .font(AppFont.editorBodyStrong)
            }
            .foregroundStyle(AppTheme.headlineText)
            .frame(width: width, height: AppTheme.compactControlHeight)
        }
        .buttonStyle(TimelineToolbarButtonStyle())
        .help(L10n.string(help))
        .accessibilityLabel(L10n.string(title))
    }

    private var timelinePanel: some View {
        TimelineSurface(padding: 0) {
            GeometryReader { panel in
                if !preview.isLoaded && viewModel.segments.isEmpty {
                    // Trạng thái rỗng vẫn phải đọc được là Timeline. Giữ surface sáng như
                    // chrome/menu, chỉ vẽ rail + rãnh mờ; không dựng track tối, waveform
                    // giả hoặc hit area Skim khiến người dùng thao tác nhầm.
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Spacer()
                            Text("SUB")
                            Spacer()
                            Text("AUDIO")
                            if AppFeatureFlags.dubbingEnabled {
                                Spacer()
                                Text("DUB")
                            }
                            Spacer()
                        }
                        .font(AppFont.editorMicro)
                        .foregroundStyle(AppTheme.timelineLabelText.opacity(0.58))
                        .frame(width: 52, height: panel.size.height)
                        .background(AppTheme.tileFill)

                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(width: AppTheme.hairlineWidth)

                        ZStack(alignment: .top) {
                            AppTheme.tileFill
                            Rectangle()
                                .fill(AppTheme.timelineRulerFill.opacity(0.38))
                                .frame(height: 28)
                            VStack(spacing: 0) {
                                Spacer()
                                Rectangle().fill(AppTheme.divider.opacity(0.55)).frame(height: AppTheme.hairlineWidth)
                                Spacer()
                                Rectangle().fill(AppTheme.divider.opacity(0.55)).frame(height: AppTheme.hairlineWidth)
                                if AppFeatureFlags.dubbingEnabled { Spacer() }
                                Spacer()
                            }
                            .padding(.top, 28)
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    let panelHeight = max(202, panel.size.height)
                    let rulerBandHeight: CGFloat = 32
                    let cueCanvasHeight = max(166, panelHeight - rulerBandHeight)
                    let dubbingTrackHeight: CGFloat = AppFeatureFlags.dubbingEnabled ? 44 : 0
                    let trackGroupHeight: CGFloat = 52 + 4 + 70 + dubbingTrackHeight
                    let trackTop = max(10, (cueCanvasHeight - trackGroupHeight) * 0.5)
                    let cueTrackCenterY = trackTop + 26
                    let waveformOffsetY = rulerBandHeight + trackTop + 56
                    let dubbingOffsetY = waveformOffsetY + 74
                    HStack(spacing: 0) {
                        GeometryReader { _ in
                            Text("SUB")
                                .position(x: 26, y: rulerBandHeight + cueTrackCenterY)
                            Text("AUDIO")
                                .position(x: 26, y: waveformOffsetY + 35)
                            if AppFeatureFlags.dubbingEnabled {
                                Text("DUB")
                                    .position(x: 26, y: dubbingOffsetY + 20)
                            }
                        }
                        .font(AppFont.editorMicro)
                        .foregroundStyle(AppTheme.timelineLabelText)
                        .frame(width: 52, height: panelHeight)
                        .background(AppTheme.timelineRulerFill)
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(width: AppTheme.hairlineWidth)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                timelineContent(
                                    cueCanvasHeight: cueCanvasHeight,
                                    cueTrackCenterY: cueTrackCenterY,
                                    waveformOffsetY: waveformOffsetY,
                                    dubbingOffsetY: dubbingOffsetY,
                                    totalHeight: panelHeight
                                )
                                    // 16 px dư chỉ nằm ở đuôi timeline. Nếu để
                                    // frame mặc định căn giữa, đầu content lệch 8 px
                                    // so với NSClipView và Skimmer không thể khớp chuột.
                                    .frame(
                                        minWidth: max(timelineWidth + 16, viewportWidth),
                                        alignment: .leading
                                    )
                            }
                            // SwiftUI vẫn có thể để AppKit dựng horizontal NSScroller theo
                            // preference hệ thống. Ẩn riêng thanh vẽ đó, còn cuộn trackpad
                            // và Shift-scroll của ScrollView vẫn giữ nguyên.
                            .background(
                                TimelineHorizontalScrollerHider { scrollView in
                                    timelineScrollView = scrollView
                                }
                                .frame(width: 1, height: 1)
                            )
                            .background(AppTheme.timelineCanvasFill)
                            .onChange(of: cueRevealRequest) { _, request in
                                guard let request,
                                      let cue = viewModel.segments.first(where: { $0.id == request.cueID })
                                else { return }

                                // Giữ nguyên khung nhìn nếu đầu cue đã thấy. Chỉ
                                // nhảy khi cue nằm ngoài viewport trái/phải.
                                if let scrollView = timelineScrollView {
                                    let clipView = scrollView.contentView
                                    let visible = clipView.bounds
                                    let cueX = CGFloat(cue.startSeconds * pixelsPerSecond)
                                    let margin: CGFloat = 18
                                    if cueX >= visible.minX + margin,
                                       cueX <= visible.maxX - margin {
                                        return
                                    }

                                    // Cuộn trực tiếp NSClipView thay vì phụ thuộc
                                    // ScrollViewReader trong cùng transaction chọn cue.
                                    let documentWidth = scrollView.documentView?.bounds.width
                                        ?? max(timelineWidth + 16, viewportWidth)
                                    let maximumOriginX = max(0, documentWidth - visible.width)
                                    let targetOriginX = min(
                                        maximumOriginX,
                                        max(0, cueX - visible.width * 0.5)
                                    )
                                    clipView.scroll(
                                        to: NSPoint(x: targetOriginX, y: visible.origin.y)
                                    )
                                    scrollView.reflectScrolledClipView(clipView)
                                    return
                                }
                                // Fallback hiếm khi probe NSScrollView chưa gắn.
                                proxy.scrollTo(
                                    timelineCueAnchorID(request.cueID),
                                    anchor: .center
                                )
                            }
                        }
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: SubtitleTimelineViewportWidthKey.self, value: proxy.size.width)
                        })
                        .onPreferenceChange(SubtitleTimelineViewportWidthKey.self) { measuredWidth in
                            // SwiftUI có thể phát một frame GeometryReader rộng 0 khi panel
                            // đang đổi layout. Giữ kích thước hợp lệ gần nhất cho Zoom Fit.
                            guard measuredWidth.isFinite, measuredWidth > 100 else { return }
                            viewportWidth = measuredWidth
                        }
                    }
                    .frame(width: panel.size.width, height: panelHeight, alignment: .top)
                }
            }
        }
    }
    private func timelineContent(
        cueCanvasHeight: CGFloat,
        cueTrackCenterY: CGFloat,
        waveformOffsetY: CGFloat,
        dubbingOffsetY: CGFloat,
        totalHeight: CGFloat
    ) -> some View {
        let width = max(timelineWidth, viewportWidth - 16)
        let displayedPlayheadTime = playheadDragTime ?? preview.currentTime
        return ZStack(alignment: .topLeading) {
            TimelineRuler(duration: duration, pixelsPerSecond: pixelsPerSecond, width: width)
                .equatable().contentShape(Rectangle()).gesture(timelinePointerDrag)

            SubtitleTimelineCueLane(
                segments: viewModel.segments,
                pixelsPerSecond: pixelsPerSecond,
                selectedIDs: selectedIDs,
                primarySelectedID: selectedID,
                cueTrackCenterY: cueTrackCenterY,
                isDarkTheme: colorScheme == .dark,
                onSelect: selectCueFromTimeline,
                onMarqueeSelection: selectCuesFromMarquee,
                onClearSelection: clearTimelineSelection,
                onTiming: applyTiming,
                onSeek: timelineClick,
                seeksOnClick: !isSkimmingActive
            )
            .frame(width: width, height: cueCanvasHeight)
            .offset(y: 32)

            SubtitleTimelineNativeWaveform(
                peaks: peaks,
                width: width,
                height: 70,
                contentID: waveformContentID,
                isDarkTheme: colorScheme == .dark
            )
                .equatable().contentShape(Rectangle()).gesture(timelinePointerDrag)
                .frame(width: width, height: 70)
                .offset(y: waveformOffsetY)
            if AppFeatureFlags.dubbingEnabled {
                let dubbingSelectionHeight = max(40, totalHeight - dubbingOffsetY)
                DubbingTimelineLane(
                    session: .shared,
                    pixelsPerSecond: pixelsPerSecond,
                    width: width,
                    height: dubbingSelectionHeight,
                    selectedIDs: selectedDubbingIDs,
                    isDarkTheme: colorScheme == .dark,
                    snapEnabled: snapEnabled,
                    snapTimes: viewModel.segments.flatMap { [$0.startSeconds, $0.endSeconds] },
                    onSelect: selectDubbingFromTimeline,
                    onMarqueeSelection: selectDubbingFromMarquee,
                    onSeek: timelineClick
                )
                .frame(width: width, height: dubbingSelectionHeight)
                .clipped()
                .offset(y: dubbingOffsetY)
            }
            ForEach(viewModel.segments) { cue in
                Color.clear
                    .frame(width: 1, height: 1)
                    .offset(x: max(0, CGFloat(cue.startSeconds * pixelsPerSecond)), y: 1)
                    .id(timelineCueAnchorID(cue.id))
                    .allowsHitTesting(false)
            }
            // Skimmer Final Cut: thanh sáng tạm theo chuột. Playhead đỏ giữ nguyên
            // cho tới khi người dùng click hoặc kéo trực tiếp playhead.
            if isSkimmingActive, let skimDisplayTime, playheadDragTime == nil {
                let x = min(width - 1, max(0, CGFloat(skimDisplayTime * pixelsPerSecond)))
                let skimmerColor: Color = colorScheme == .dark
                    ? .white.opacity(0.9)
                    : AppTheme.titleText.opacity(0.7)
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(skimmerColor)
                        .frame(width: 10, height: 7)
                    Rectangle()
                        .fill(skimmerColor)
                        .frame(width: 1, height: max(1, totalHeight - 24))
                }
                .frame(width: 10, height: max(1, totalHeight - 17), alignment: .top)
                .offset(x: x - 5, y: 17)
                .allowsHitTesting(false)
            }
            if hasCommittedPlayhead || preview.isPlaying || playheadDragTime != nil {
                Rectangle().fill(AppTheme.accentRed).frame(width: 1.5, height: max(1, totalHeight - 17))
                    .offset(x: min(width - 1.5, max(0, CGFloat(displayedPlayheadTime * pixelsPerSecond))), y: 17)
                    .allowsHitTesting(false)
                // Nét đỏ giữ mảnh, nhưng vùng bắt 18 px để có thể chụp và kéo như playhead editor.
                Color.clear
                    .frame(width: 18, height: max(1, totalHeight - 17))
                    .contentShape(Rectangle())
                    .offset(x: min(width - 1.5, max(0, CGFloat(displayedPlayheadTime * pixelsPerSecond))) - 9, y: 17)
                    .gesture(playheadDrag)
                    .onHover { hovering in
                        if hovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                    }
            }
            if !skimming, let marker = clickMarkerTime {
                Rectangle().fill(AppTheme.timelineClickMarker).frame(width: 1.5, height: max(1, totalHeight - 17))
                    .offset(x: min(width - 1.5, max(0, CGFloat(marker * pixelsPerSecond))), y: 17)
                    .allowsHitTesting(false)
            }
        }
        .background(AppTheme.timelineCanvasFill)
        .frame(width: width, height: totalHeight, alignment: .top)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                updateHoverPointer(at: point.x)
            case .ended:
                skimTime = nil
                skimDisplayTime = nil
                skimViewportX = nil
            }
        }
    }

    private func timelineCueAnchorID(_ id: Int) -> String { "timeline-cue-\(id)" }

    private func synchronizeDubbingIfEnabled() {
        guard AppFeatureFlags.dubbingEnabled else { return }
        DubbingSessionModel.shared.synchronize(cues: viewModel.segments)
    }

    private func synchronizeDubbingPreview() {
        guard AppFeatureFlags.dubbingEnabled else { return }
        dubbingSession.synchronizePreviewPlayback(at: preview.currentTime, isPlaying: preview.isPlaying)
    }

    private func finishCueEditing() {
        guard editingCueID != nil else { return }
        editingCueID = nil
    }

    private func selectCueFromPanel(_ cue: SRTSegment, intent: TimelineCueSelectionIntent) {
        finishCueEditing()
        activateSubtitleSelection()
        cueRevealRequest = CueRevealRequest(cueID: cue.id, token: UUID())
        updateSelection(id: cue.id, intent: intent)
        hasCommittedPlayhead = true
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        seek(cue.startSeconds)
    }

    private func openCueTextEditor(_ cue: SRTSegment) {
        finishCueEditing()
        activateSubtitleSelection()
        cueRevealRequest = CueRevealRequest(cueID: cue.id, token: UUID())
        cueSelection.replace(with: cue.id)
        hasCommittedPlayhead = true
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        seek(cue.startSeconds)
        editingCueID = cue.id
    }

    private func selectCueFromTimeline(_ id: Int, intent: TimelineCueSelectionIntent) {
        finishCueEditing()
        activateSubtitleSelection()
        updateSelection(id: id, intent: intent)
        cuePanelRevealRequest = CueRevealRequest(cueID: id, token: UUID())
    }

    private func selectCuesFromMarquee(_ ids: Set<Int>) {
        finishCueEditing()
        activateSubtitleSelection()
        cueSelection.replace(with: ids, orderedIDs: viewModel.segments.map(\.id))
    }

    private func selectDubbingFromTimeline(_ id: Int, intent: TimelineCueSelectionIntent) {
        finishCueEditing()
        activateDubbingSelection()
        dubbingSelection.select(
            id: id,
            intent: intent,
            orderedIDs: dubbingSession.effectiveRenderedCues.map(\.id)
        )
    }

    private func selectDubbingFromMarquee(_ ids: Set<Int>) {
        finishCueEditing()
        activateDubbingSelection()
        dubbingSelection.replace(
            with: ids,
            orderedIDs: dubbingSession.effectiveRenderedCues.map(\.id)
        )
    }

    private func activateSubtitleSelection() {
        timelineSelectionFocus = .subtitle
        dubbingSelection.clear()
    }

    private func activateDubbingSelection() {
        timelineSelectionFocus = .dubbing
        cueSelection.clear()
    }

    private func clearTimelineSelection() {
        cueSelection.clear()
        dubbingSelection.clear()
        timelineSelectionFocus = .subtitle
    }

    private func updateSelection(id: Int, intent: TimelineCueSelectionIntent) {
        cueSelection.select(id: id, intent: intent, orderedIDs: viewModel.segments.map(\.id))
    }

    private func selectAllCues() {
        cueSelection.selectAll(orderedIDs: viewModel.segments.map(\.id))
    }

    private func applyTiming(_ id: Int, _ start: Double, _ end: Double) {
        guard let cue = viewModel.segments.first(where: { $0.id == id }) else { return }
        let snapped = snap(start: start, end: end, excluding: id)
        guard abs(cue.startSeconds - snapped.0) > 0.000_5 || abs(cue.endSeconds - snapped.1) > 0.000_5,
              let editedIndex = viewModel.segments.firstIndex(where: { $0.id == id }) else { return }

        var updated = viewModel.segments
        updated[editedIndex] = SRTSegmentEditor.withTiming(updated[editedIndex], start: snapped.0, end: snapped.1)
        rippleAdjacentCues(&updated, editedID: id)
        viewModel.applyEditSegments(updated)
        cueSelection.replace(with: id)
        seek(snapped.0)
    }

    /// Cue đang kéo có ưu tiên. Nếu nó chạm cue bên cạnh, mép cue bên cạnh tự
    /// lùi/tiến theo để các cue không bao giờ chồng thời gian lên nhau.
    private func rippleAdjacentCues(_ segments: inout [SRTSegment], editedID: Int) {
        let minimumDuration = 0.05
        let order = segments.indices.sorted { segments[$0].startSeconds < segments[$1].startSeconds }
        guard let editedPosition = order.firstIndex(where: { segments[$0].id == editedID }) else { return }

        // Cue trước co phần cuối lại khi cue đang kéo lấn về bên trái.
        var nextStart = segments[order[editedPosition]].startSeconds
        if editedPosition > 0 {
            for position in stride(from: editedPosition - 1, through: 0, by: -1) {
                let index = order[position]
                guard segments[index].endSeconds > nextStart else { break }
                let newEnd = nextStart
                let newStart = min(segments[index].startSeconds, newEnd - minimumDuration)
                segments[index] = SRTSegmentEditor.withTiming(segments[index], start: max(0, newStart), end: max(minimumDuration, newEnd))
                nextStart = segments[index].startSeconds
            }
        }

        // Cue sau thụt mép đầu; nếu bị đẩy hết độ dài tối thiểu thì chuỗi phía
        // sau tiếp tục dời ra, thay vì chồng lên nhau.
        var previousEnd = segments[order[editedPosition]].endSeconds
        if editedPosition + 1 < order.count {
            for position in (editedPosition + 1)..<order.count {
                let index = order[position]
                guard segments[index].startSeconds < previousEnd else { break }
                let newStart = previousEnd
                let newEnd = max(segments[index].endSeconds, newStart + minimumDuration)
                segments[index] = SRTSegmentEditor.withTiming(segments[index], start: newStart, end: newEnd)
                previousEnd = newEnd
            }
        }
    }
    private func splitSelected() {
        guard timelineSelectionFocus == .subtitle,
              selectedIDs.count == 1,
              let id = selectedID,
              viewModel.splitSegment(id: id) else { return }
        cueSelection.replace(with: id)
    }
    private func mergeSelected() {
        guard canMergeSelectedCues, let firstIndex = selectedIndices.first else { return }
        let mergedStart = viewModel.segments[firstIndex].startSeconds
        guard viewModel.mergeSegments(ids: selectedIDs), viewModel.segments.indices.contains(firstIndex) else { return }
        let mergedID = viewModel.segments[firstIndex].id
        cueSelection.replace(with: mergedID)
        editingCueID = nil
        seek(mergedStart)
    }
    private func deleteSelected() {
        if timelineSelectionFocus == .dubbing {
            guard !selectedDubbingIDs.isEmpty else { return }
            dubbingSession.removeRenderedCues(cueIDs: selectedDubbingIDs)
            dubbingSelection.clear()
            return
        }
        guard canDeleteSelectedCues, let firstIndex = selectedIndices.first,
              viewModel.deleteSegments(ids: selectedIDs) else { return }
        guard !viewModel.segments.isEmpty else {
            cueSelection.clear()
            editingCueID = nil
            return
        }
        let nextIndex = min(firstIndex, viewModel.segments.count - 1)
        let nextID = viewModel.segments[nextIndex].id
        cueSelection.replace(with: nextID)
        editingCueID = nil
    }
    /// Chỉ bỏ phần phía được yêu cầu của cue chọn. Reference là Skim khi con trỏ
    /// đang ở Timeline, giúp thao tác đúng cue/tile mà không phải kéo playhead đỏ.
    private func deleteSelectedLeftSide() {
        guard let cue = selectedCue, canDeleteSelectedCueSide else { return }
        applyTiming(cue.id, sideDeleteReferenceTime, cue.endSeconds)
    }
    private func deleteSelectedRightSide() {
        guard let cue = selectedCue, canDeleteSelectedCueSide else { return }
        applyTiming(cue.id, cue.startSeconds, sideDeleteReferenceTime)
    }
    private func seek(_ seconds: Double) { preview.seekForEdit(seconds: max(0, min(duration, seconds))) }
    private var timelinePointerDrag: some Gesture { DragGesture(minimumDistance: 0).onChanged { value in if timelineDragStartX == nil { timelineDragStartX = value.startLocation.x }; guard let start = timelineDragStartX, abs(value.location.x - start) >= 2 else { return }; updateDragSkim(at: value.location.x) }.onEnded { value in timelineDragStartX = nil; endPointer(at: value.location.x) } }
    private var playheadDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                hasCommittedPlayhead = true
                if playheadDragStartTime == nil { playheadDragStartTime = preview.currentTime }
                guard let start = playheadDragStartTime else { return }
                let time = snappedTimelineTime(start + Double(value.translation.width) / pixelsPerSecond)
                playheadDragTime = time
                preview.skimForPreview(seconds: time)
            }
            .onEnded { value in
                defer { playheadDragStartTime = nil; playheadDragTime = nil; NSCursor.openHand.set() }
                guard let start = playheadDragStartTime else { return }
                let time = max(0, min(duration, start + Double(value.translation.width) / pixelsPerSecond))
                seek(time)
            }
    }
    private func pointerXInTimelineViewport() -> CGFloat? {
        guard let scrollView = timelineScrollView,
              let window = scrollView.window else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let pointInViewport = scrollView.contentView.convert(pointInWindow, from: nil)
        let bounds = scrollView.contentView.bounds
        // `convert` trả điểm trong toạ độ bounds của NSClipView (đã gồm origin
        // khi đang scroll). Trừ origin một lần để có đúng vị trí hiển thị dưới
        // con trỏ; trước đây thiếu bước này khiến Skim lệch dần khi cuộn ngang.
        let viewportX = pointInViewport.x - bounds.origin.x
        guard viewportX >= -2, viewportX <= bounds.width + 2 else { return nil }
        return viewportX
    }

    private func timelineTimeUnderPointer(fallbackX: CGFloat) -> Double {
        let viewportX = pointerXInTimelineViewport() ?? fallbackX
        let contentX: CGFloat
        if let scrollView = timelineScrollView {
            contentX = scrollView.contentView.bounds.origin.x + viewportX
        } else {
            contentX = viewportX
        }
        return snappedTimelineTime(Double(contentX) / pixelsPerSecond)
    }

    /// Zoom không được neo vào Skim vì Skim có thể Snap sang mép cue. Đây là
    /// thời điểm thô đúng ngay dưới con trỏ, dùng riêng cho Zoom keyboard/slider.
    private func rawTimelineTimeUnderPointer() -> Double? {
        guard let viewportX = pointerXInTimelineViewport() else { return nil }
        let originX = timelineScrollView?.contentView.bounds.origin.x ?? 0
        return max(0, min(duration, Double(originX + viewportX) / pixelsPerSecond))
    }

    private func updateHoverPointer(at x: CGFloat) {
        // Zoom vẫn neo raw mouse time riêng. Skim chỉ rời đúng pixel chuột khi
        // user chủ động bật Snap và đang ở gần playhead/đầu/đuôi một cue.
        skimViewportX = pointerXInTimelineViewport() ?? x
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard isSkimmingActive else {
            skimDisplayTime = nil
            skimTime = nil
            return
        }
        let rawTime = rawTimelineTimeUnderPointer()
            ?? max(0, min(duration, Double(x) / pixelsPerSecond))
        let displayedTime = snappedTimelineTime(rawTime)
        skimDisplayTime = displayedTime
        skimTime = displayedTime
        preview.skimForPreview(seconds: displayedTime)
    }
    private func updateDragSkim(at x: CGFloat) {
        guard isSkimmingActive else { return }
        skimViewportX = pointerXInTimelineViewport() ?? x
        let rawTime = rawTimelineTimeUnderPointer() ?? max(0, min(duration, Double(x) / pixelsPerSecond))
        let displayedTime = snappedTimelineTime(rawTime)
        skimDisplayTime = displayedTime
        skimTime = displayedTime
        preview.skimForPreview(seconds: displayedTime)
    }
    private func endPointer(at x: CGFloat) {
        // Chốt đúng time mà vạch trắng vừa hiển thị (raw hoặc đã Snap). Không
        // chạy Snap thêm lúc mouse-up vì sẽ làm thanh đỏ nhảy khỏi điểm đang thấy.
        let visibleSkimTime = isSkimmingActive ? skimTime : nil
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        let rawTime = rawTimelineTimeUnderPointer() ?? max(0, min(duration, Double(x) / pixelsPerSecond))
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.contains(.command), !flags.contains(.shift) {
            clearTimelineSelection()
        }
        timelineClick(visibleSkimTime ?? rawTime)
    }
    private func timelineClick(_ seconds: Double) {
        let time = max(0, min(duration, seconds))
        hasCommittedPlayhead = true
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        if !isSkimmingActive { clickMarkerTime = time }
        seek(time)
    }
    private func setSkimming(_ enabled: Bool) {
        skimming = enabled
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        if enabled { clickMarkerTime = nil }
    }

    /// Space và nút Phát: nếu chuột đang ở Timeline thì đó là điểm chốt mới.
    /// Nếu chuột ở nơi khác, tiếp tục phát từ playhead đỏ đã chốt.
    private func togglePlaybackFromPointer() {
        if preview.isPlaying {
            preview.pause()
            return
        }
        let startTime = rawTimelineTimeUnderPointer() ?? preview.currentTime
        hasCommittedPlayhead = true
        skimTime = nil
        skimDisplayTime = nil
        skimViewportX = nil
        preview.seek(seconds: startTime, playAfter: true, precise: true)
    }
    /// Với Skim đang bật, thời điểm dưới chuột giữ nguyên vị trí trên màn hình
    /// khi zoom. Cách này khiến zoom cue/waveform/preview có cùng "tâm" như FCP.
    private func applyTimelineZoom(_ candidate: Double) {
        let next = min(260, max(0.01, candidate))
        let previous = pixelsPerSecond
        guard abs(next - previous) > 0.000_001 else { return }

        let mousePivotTime = rawTimelineTimeUnderPointer()
        let pivotTime = mousePivotTime ?? (isSkimmingActive ? skimTime : nil)
        let scrollView = timelineScrollView
        let oldOriginX = scrollView?.contentView.bounds.origin.x ?? 0
        let pointerX = pointerXInTimelineViewport()
            ?? skimViewportX
            ?? pivotTime.map { CGFloat($0 * previous) - oldOriginX }

        pixelsPerSecond = next

        guard let pivotTime, let pointerX, let scrollView else { return }
        Task { @MainActor in
            // Chờ SwiftUI áp dụng chiều rộng canvas mới trước khi thay đổi origin.
            guard abs(pixelsPerSecond - next) < 0.000_001 else { return }
            let contentWidth = max(CGFloat(duration * next) + 16, viewportWidth)
            let visibleWidth = scrollView.contentView.bounds.width
            let maximumOrigin = max(0, contentWidth - visibleWidth)
            let desiredOrigin = CGFloat(pivotTime * next) - pointerX
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: min(maximumOrigin, max(0, desiredOrigin)), y: scrollView.contentView.bounds.origin.y)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func zoomIn() { applyTimelineZoom(pixelsPerSecond * 1.4) }
    private func zoomOut() { applyTimelineZoom(pixelsPerSecond / 1.4) }
    /// Tương đương Shift Z của Final Cut: fit toàn bộ duration thật của audio vào vùng timeline.
    private func zoomToFit() {
        guard duration.isFinite, duration > 0 else { return }
        // `viewportWidth` là chính phần ScrollView Timeline đang thấy. `+16` là
        // phần đệm inner canvas, nên trừ nó để content rộng đúng bằng viewport.
        // Overview cần thấy trọn audio đúng bề ngang; renderer waveform tự cap
        // tile để mức rất thấp vẫn an toàn, không còn crash khi kéo về min.
        let clipWidth = timelineScrollView?.contentView.bounds.width ?? 0
        let safeViewportWidth = clipWidth.isFinite && clipWidth > 100
            ? clipWidth
            : (viewportWidth.isFinite && viewportWidth > 100 ? viewportWidth : 900)
        let drawableWidth = max(100, safeViewportWidth - 16)
        applyTimelineZoom(Double(drawableWidth) / duration)
    }
    /// Chung cho Skim, click Timeline và kéo playhead. Cùng tolerance với thao tác
    /// trim để cảm giác Snap nhất quán ở mọi vị trí thời gian.
    private func snappedTimelineTime(_ seconds: Double) -> Double {
        let raw = max(0, min(duration, seconds))
        guard snapEnabled else { return raw }
        let tolerance = min(0.75, 8 / pixelsPerSecond)
        let cueTarget = nearestCueSnapEdge(to: raw, excluding: nil)
        let previewTarget = preview.currentTime
        let target = [cueTarget, previewTarget].compactMap { $0 }
            .min(by: { abs($0 - raw) < abs($1 - raw) })
        guard let target, abs(target - raw) <= tolerance else {
            return raw
        }
        return target
    }
    private func snap(start: Double, end: Double, excluding id: Int) -> (Double, Double) {
        guard snapEnabled else { return (start, end) }
        let tolerance = min(0.75, 8 / pixelsPerSecond)
        let startTargets = [nearestCueSnapEdge(to: start, excluding: id), preview.currentTime].compactMap { $0 }
        if let target = startTargets.min(by: { abs($0 - start) < abs($1 - start) }),
           abs(target - start) <= tolerance {
            let length = end - start
            return (target, target + length)
        }
        let endTargets = [nearestCueSnapEdge(to: end, excluding: id), preview.currentTime].compactMap { $0 }
        if let target = endTargets.min(by: { abs($0 - end) < abs($1 - end) }),
           abs(target - end) <= tolerance {
            return (start, target)
        }
        return (start, end)
    }

    private func refreshCueSnapEdges() {
        cueSnapEdges = viewModel.segments.flatMap { cue in
            [SnapEdge(cueID: cue.id, time: cue.startSeconds), SnapEdge(cueID: cue.id, time: cue.endSeconds)]
        }.filter { $0.time.isFinite }
            .sorted { $0.time < $1.time }
    }

    /// Tìm nhị phân trên edge đã cache; drag/trim không còn cấp phát và quét
    /// toàn bộ cue ở mỗi mouse event khi project có hàng nghìn subtitle.
    private func nearestCueSnapEdge(to value: Double, excluding cueID: Int?) -> Double? {
        guard !cueSnapEdges.isEmpty else { return nil }
        var low = 0
        var high = cueSnapEdges.count
        while low < high {
            let mid = (low + high) / 2
            if cueSnapEdges[mid].time < value { low = mid + 1 } else { high = mid }
        }

        var left = low - 1
        var right = low
        var bestTime: Double?
        var bestDistance = Double.infinity
        while left >= 0 || right < cueSnapEdges.count {
            let leftDistance = left >= 0 ? abs(cueSnapEdges[left].time - value) : .infinity
            let rightDistance = right < cueSnapEdges.count ? abs(cueSnapEdges[right].time - value) : .infinity
            if min(leftDistance, rightDistance) > bestDistance { break }

            if leftDistance <= rightDistance, left >= 0 {
                let edge = cueSnapEdges[left]
                if edge.cueID != cueID, leftDistance < bestDistance {
                    bestDistance = leftDistance
                    bestTime = edge.time
                }
                left -= 1
            } else if right < cueSnapEdges.count {
                let edge = cueSnapEdges[right]
                if edge.cueID != cueID, rightDistance < bestDistance {
                    bestDistance = rightDistance
                    bestTime = edge.time
                }
                right += 1
            }
        }
        return bestTime
    }
    private func reloadWaveform() {
        peaks = []
        waveformDuration = 0
        waveformContentID = UUID()
        guard let url = viewModel.mediaURL else { return }
        Task {
            // Service lấy duration trước rồi tự chọn peak density; không phụ thuộc
            // AVPlayer đã kịp publish duration hay chưa.
            if let result = try? await WaveformPeakService.loadPeaks(url: url) {
                guard viewModel.mediaURL == url else { return }
                peaks = result.peaks
                waveformDuration = result.duration
                waveformContentID = UUID()
            }
        }
    }
    private func timecode(_ value: Double) -> String { SRTTimecode.formatPrecise(value).replacingOccurrences(of: ",", with: ":") }
    private func closeProject() { if let url = viewModel.mediaURL { viewModel.deleteRecentProject(at: url.path) } else { removeSRT() } }
    private func removeMedia() { preview.clear(); viewModel.mediaURL = nil; viewModel.whisperDraftMediaURL = nil; waveformDuration = 0; peaks = [] }
    private func removeSRT() {
        viewModel.segments = []
        viewModel.srtURL = nil
        cueSelection.clear()
        dubbingSelection.clear()
        timelineSelectionFocus = .subtitle
        viewModel.resetEditHistory()
    }
    private func chooseMedia() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .audio]; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { viewModel.setMediaURL(url); viewModel.setWhisperDraftMedia(url); viewModel.setScriptDraftMedia(url) } }
    private func chooseSRT() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "srt")!]; if panel.runModal() == .OK, let url = panel.url { viewModel.mediaURL == nil ? viewModel.openStandaloneSRT(url) : viewModel.openExistingSRT(url, mediaAlreadySet: true) } }
    private func handleImportDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.pathExtension.lowercased() == "srt" {
                        self.viewModel.mediaURL == nil
                            ? self.viewModel.openStandaloneSRT(url)
                            : self.viewModel.openExistingSRT(url, mediaAlreadySet: true)
                    } else {
                        self.viewModel.setMediaURL(url)
                        self.viewModel.setWhisperDraftMedia(url)
                        self.viewModel.setScriptDraftMedia(url)
                    }
                }
            }
        }
        return !providers.isEmpty
    }
    private func beginWhisper() {
        guard let mediaURL = viewModel.mediaURL else { chooseMedia(); return }
        viewModel.setWhisperDraftMedia(mediaURL)
        guard GroqCredentialStore.hasKey else { viewModel.openGroqSettings(); return }
        viewModel.runWhisper()
    }
    private func beginScriptSubtitle() {
        guard let mediaURL = viewModel.mediaURL else { chooseMedia(); return }
        viewModel.setScriptDraftMedia(mediaURL)
        isScriptSheetOpen = true
    }
    private func installShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Khi đang gõ nội dung cue, mọi phím vẫn thuộc về trình soạn thảo.
            guard !(event.window?.firstResponder is NSTextView) else { return event }

            let defaults = UserDefaults.standard
            func matches(_ storageKey: String, _ fallback: String) -> Bool {
                TimelineShortcutSpec.matches(
                    event,
                    stored: defaults.string(forKey: storageKey) ?? fallback,
                    fallback: fallback
                )
            }

            if matches("msm.timeline.shortcut.zoomIn", "command+plus") {
                zoomIn(); return nil
            }
            if matches("msm.timeline.shortcut.zoomOut", "command+minus") {
                zoomOut(); return nil
            }
            if matches("msm.timeline.shortcut.zoomFit", "shift+z") {
                zoomToFit(); return nil
            }
            if matches("msm.timeline.shortcut.undo", "command+z") {
                guard viewModel.canUndoEdit else { return nil }
                viewModel.undoEdit()
                return nil
            }
            if matches("msm.timeline.shortcut.redo", "command+shift+z") {
                guard viewModel.canRedoEdit else { return nil }
                viewModel.redoEdit()
                return nil
            }
            if matches("msm.timeline.shortcut.selectAll", "command+a") {
                if timelineSelectionFocus == .dubbing {
                    let ids = dubbingSession.effectiveRenderedCues.map(\.id)
                    guard !ids.isEmpty else { return nil }
                    dubbingSelection.selectAll(orderedIDs: ids)
                } else {
                    guard !viewModel.segments.isEmpty else { return nil }
                    selectAllCues()
                }
                return nil
            }
            if matches("msm.timeline.shortcut.delete", "delete") {
                guard canDeleteTimelineSelection else { return nil }
                deleteSelected()
                return nil
            }
            if matches("msm.timeline.shortcut.play", "space") {
                togglePlaybackFromPointer()
                return nil
            }
            if matches("msm.timeline.shortcut.back", "j") {
                seek(preview.currentTime - 1.0 / 24)
                return nil
            }
            if matches("msm.timeline.shortcut.forward", "l") {
                seek(preview.currentTime + 1.0 / 24)
                return nil
            }
            if matches("msm.timeline.shortcut.skim", "s") {
                guard !preview.isPlaying else { return nil }
                setSkimming(!skimming)
                return nil
            }
            if matches("msm.timeline.shortcut.trimLeft", "option+left") {
                deleteSelectedLeftSide()
                return nil
            }
            if matches("msm.timeline.shortcut.trimRight", "option+right") {
                deleteSelectedRightSide()
                return nil
            }
            if matches("msm.timeline.shortcut.split", "x") {
                splitSelected()
                return nil
            }
            if matches("msm.timeline.shortcut.merge", "g") {
                mergeSelected()
                return nil
            }
            return event
        }
    }
    private func removeShortcuts() { if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil } }
}
