import SwiftUI

@MainActor
enum SubtitleWorkspacePanels {
    @ViewBuilder
    static func videoPreview(
        minHeight: CGFloat,
        frameHeight: CGFloat? = nil,
        preview: AVPreviewService,
        segments: [SRTSegment] = [],
        style: SubtitleBurnStyle? = nil,
        focusSegmentID: Int? = nil,
        liveEditDraft: (id: Int, text: String)? = nil,
        showSubtitleOverlay: Bool = false,
        showHeader: Bool = false,
        whisperProgressPercent: Int? = nil,
        stylePanelIsOpen: Binding<Bool>? = nil,
        stylePanelEnabled: Bool = false,
        stylePanelIcon: String = "character.textbox",
        stylePanelHelp: String = "Kiểu sub"
    ) -> some View {
        let boxH = frameHeight ?? minHeight
        let pad = AppTheme.workspaceCellPadding
        let gap = AppTheme.workspaceCellStackGap
        let transportH = AppTheme.workspaceTransportRowHeight

        let videoDisplaySize = preview.currentURL.map { VideoGeometryProbe.displaySize(for: $0) }
            ?? CGSize(width: 1920, height: 1080)
        let videoAspect = max(0.01, videoDisplaySize.width / max(videoDisplaySize.height, 1))
        let referencePixelHeight = VideoPreviewFrame.classify(displaySize: videoDisplaySize)
            .referencePixelSize.height
        // Nền họa tiết khi chưa có video.
        let showStyleStage = !preview.isLoaded && style != nil

        let playerArea = Group {
            if preview.isLoaded {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if let player = preview.player {
                            AVPlayerContainerView(player: player, showsBuiltInControls: false)
                        } else if let style {
                            // SRT độc lập: vẫn hiển thị cue theo timecode trên stage,
                            // nhưng không có video/audio và không thể lẫn với project cũ.
                            SubtitlePreviewStyleStage(style: style)
                        } else {
                            Color.black.opacity(0.92)
                        }
                        // Preview = text timeline. (Trước: ẩn sub khi có % → “100% rồi mới phọt sub”.)
                        if showSubtitleOverlay,
                           let style, !segments.isEmpty,
                           let overlay = SubtitlePreviewOverlayView.make(
                               segments: segments,
                               currentTime: preview.currentTime,
                               style: style,
                               focusSegmentID: focusSegmentID,
                               isPlaying: preview.isPlaying,
                               liveEditDraft: liveEditDraft,
                               videoAspectRatio: videoAspect,
                               referencePixelHeight: referencePixelHeight
                           ) {
                            overlay
                        }

                        // Job % — vẽ trên cùng; không chặn sub ở dưới.
                        if let pct = whisperProgressPercent {
                            PreviewJobProgressOverlay(percent: pct)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }

                    if let stylePanelIsOpen {
                        PreviewCornerPanelToggle(
                            isOpen: stylePanelIsOpen.wrappedValue,
                            icon: stylePanelIcon,
                            isEnabled: stylePanelEnabled,
                            helpText: stylePanelHelp
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                stylePanelIsOpen.wrappedValue.toggle()
                            }
                        }
                        .padding(8)
                    }
                }
                .aspectRatio(videoAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if showStyleStage, let style {
                // Chưa có video — chỉ nền + gợi ý (font/màu vẫn chỉnh ở panel phải).
                SubtitlePreviewStyleStage(style: style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.mutedText.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppFieldSurface(radius: 10))
            }
        }

        let playerContent = VStack(alignment: .leading, spacing: gap) {
            playerArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PreviewTransportBar(
                preview: preview,
                jobProgressPercent: whisperProgressPercent
            )
            .frame(height: transportH)
        }

        if showHeader {
            AppCard(title: "Xem trước", subtitle: nil) {
                playerContent
            }
        } else {
            playerContent
                .padding(pad)
                .frame(height: boxH)
                .background(AppTileSurface())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    static func transcript(
        minHeight: CGFloat,
        frameHeight: CGFloat? = nil,
        segments: [SRTSegment],
        currentTime: Double,
        isPlaying: Bool,
        srtURL: URL?,
        canSwitchVariant: Bool = false,
        variantViewingLabel: String = "",
        variantToggleHint: String = "",
        onToggleVariant: (() -> Void)? = nil,
        onSeek: @escaping (SRTSegment) -> Void,
        @ViewBuilder translateAccessory: () -> some View = { EmptyView() },
        onCopy: @escaping () -> Void,
        onExportTXT: @escaping () -> Void,
        onExportSRT: @escaping () -> Void,
        onExportXML: (() -> Void)? = nil,
        onRevealFolder: (() -> Void)? = nil,
        showHeader: Bool = false
    ) -> some View {
        let activeID = segments.segmentID(at: currentTime)

        let listContent = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if canSwitchVariant, let onToggleVariant {
                    SubtitleVariantSwitcher(
                        label: variantViewingLabel,
                        hint: variantToggleHint,
                        action: onToggleVariant
                    )
                }

                Spacer(minLength: 8)

                translateAccessory()
                AppPillButton(title: "Sao chép", icon: "doc.on.doc", tint: AppTheme.accentBlue, filled: false, action: onCopy)
                AppPillButton(title: "TXT", icon: "doc.text", tint: AppTheme.accentBlue, filled: false, action: onExportTXT)
                AppPillButton(title: "SRT", icon: "captions.bubble", tint: AppTheme.accentBlue, filled: false, action: onExportSRT)
                if let onExportXML {
                    AppPillButton(title: "XML", icon: "film", tint: AppTheme.accentBlue, filled: false, action: onExportXML)
                }
                if let onRevealFolder {
                    AppPillButton(title: "Thư mục", icon: "folder", tint: AppTheme.accentBlue, filled: false, action: onRevealFolder)
                } else if let srtURL {
                    AppPillButton(title: "Thư mục", icon: "folder", tint: AppTheme.accentBlue, filled: false) {
                        SRTExportService.revealInFinder(srtURL)
                    }
                }
            }
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(segments) { segment in
                            let isActive = activeID == segment.id
                            Button {
                                onSeek(segment)
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Text(segment.startLabel)
                                        .font(AppFont.mono)
                                        .foregroundStyle(isActive ? AppTheme.accentGreen : AppTheme.accentBlue)
                                        .frame(width: 72, alignment: .leading)
                                    Text(segment.text)
                                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                                        .foregroundStyle(isActive ? AppTheme.headlineText : AppTheme.bodyText)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isActive ? AppTheme.accentGreen.opacity(0.14) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(AppPlainButtonStyle())
                            .id(segment.id)

                            if segment.id != segments.last?.id {
                                Divider().opacity(0.2)
                            }
                        }
                    }
                }
                .onChange(of: activeID) { _, newID in
                    guard isPlaying, let newID else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)

        let boxH = frameHeight ?? minHeight

        if showHeader {
            AppCard(title: "Bản chép lời", subtitle: nil) {
                listContent
            }
        } else {
            listContent
                .padding(12)
                .frame(height: boxH)
                .background(AppTileSurface())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        }
    }

    /// Spinner + thanh tiến trình khi đang chép lời (không hiện số %).
    @ViewBuilder
    static func whisperProgressPanel(
        minHeight: CGFloat,
        frameHeight: CGFloat? = nil,
        progressPercent: Int
    ) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.35)
                .tint(AppTheme.accentOrange)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.divider.opacity(0.35))
                    Capsule()
                        .fill(AppTheme.accentOrange.opacity(0.7))
                        .frame(width: max(4, geo.size.width * CGFloat(progressPercent) / 100))
                        .animation(.linear(duration: 0.22), value: progressPercent)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: frameHeight ?? minHeight)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}
