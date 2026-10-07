import SwiftUI

struct DubbingInspectorPanel: View {
    @ObservedObject var session: DubbingSessionModel
    let cues: [SRTSegment]

    private var readyCount: Int { session.renderedByCueID.count }
    private var reviewCount: Int {
        session.effectiveRenderedCues.filter { $0.fit == .needsReview }.count
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                voiceCard
                mixCard
            }
            .padding(14)
            HiddenNativeScrollerConfigurator()
                .frame(width: 1, height: 1)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            session.synchronize(cues: cues)
        }
        .onChange(of: cues) { _, next in session.synchronize(cues: next) }
        .onChange(of: session.languageIdentifier) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.voiceIdentifier) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.speechProvider) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.googleModel) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.googleVoiceIdentifier) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.maziaoModel) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.maziaoVoiceIdentifier) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.elevenModel) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.elevenVoiceIdentifier) { _, _ in session.synchronize(cues: cues) }
        .onChange(of: session.speechRate) { _, _ in session.synchronize(cues: cues) }
        .task(id: voiceCatalogTaskID) {
            switch session.speechProvider {
            case .googleCloud where session.hasGoogleCredential && session.googleVoices.isEmpty:
                await session.refreshGoogleVoiceCatalog()
            case .maziao where session.hasMaziaoCredential && session.maziaoVoices.isEmpty:
                await session.refreshMaziaoVoiceCatalog()
            case .elevenLabs where session.hasElevenLabsCredential && session.elevenVoices.isEmpty:
                await session.refreshElevenVoiceCatalog()
            default:
                break
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isRendering ? AppTheme.accentOrange : (readyCount > 0 ? AppTheme.accentGreen : AppTheme.mutedText))
                    .frame(width: 8, height: 8)
                Text(L10n.format("%d / %d cue đã có giọng", readyCount, cues.count))
                    .font(AppFont.label)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer(minLength: 0)
            }
            if session.isRendering, session.progressTotal > 0 {
                ProgressView(value: Double(session.progressCurrent), total: Double(session.progressTotal))
                    .progressViewStyle(.linear)
            }
            if reviewCount > 0 {
                Label(
                    L10n.format("%d cue có giọng dài hơn title", reviewCount),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.accentOrange)
            }
            if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(12)
        .background(AppTileSurface())
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                        .fill(AppTheme.controlFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                                .strokeBorder(AppTheme.tileStroke, lineWidth: AppTheme.hairlineWidth)
                        }
                    Image(systemName: session.speechProvider.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.speechProvider.label)
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppTheme.headlineText)
                    Label(
                        session.selectedProviderReady ? "Sẵn sàng" : "Chưa kết nối",
                        systemImage: session.selectedProviderReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(AppFont.caption)
                    .foregroundStyle(session.selectedProviderReady ? AppTheme.accentGreen : AppTheme.accentOrange)
                }
                Spacer(minLength: 0)
            }

            Divider().opacity(0.45)
            selectionRow("Mô hình") { modelSelector }
            selectionRow("Giọng nói") { voiceSelector }
            if !selectedCatalogError.isEmpty {
                Text(selectedCatalogError)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.accentOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AppPillButton(
                title: "Mở Cài đặt Lồng tiếng",
                icon: "slider.horizontal.3",
                tint: AppTheme.accentBlue,
                filled: false
            ) {
                AppCoordinator.shared.openSettings(tab: .dubbing)
            }
        }
        .padding(12)
        .background(AppTileSurface())
    }

    private var mixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trộn âm")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            compactSliderRow(
                "Tốc độ đọc",
                value: Binding(
                    get: { Double(session.speechRate) },
                    set: { session.speechRate = Float($0) }
                ),
                range: 0.38...0.62,
                display: String(format: "%.0f%%", normalizedRatePercent)
            )
            compactSliderRow(
                "Tiếng gốc",
                value: Binding(
                    get: { Double(session.originalVolume) },
                    set: { session.originalVolume = Float($0) }
                ),
                range: 0...1,
                display: "\(Int(session.originalVolume * 100))%"
            )
            compactSliderRow(
                "Giọng lồng tiếng",
                value: Binding(
                    get: { Double(session.dubVolume) },
                    set: { session.dubVolume = Float($0) }
                ),
                range: 0...1,
                display: "\(Int(session.dubVolume * 100))%"
            )
            Toggle("Tự giảm tiếng gốc khi có lời Việt", isOn: $session.duckOriginal)
                .font(AppFont.caption)
        }
        .padding(12)
        .background(AppTileSurface())
    }

    private func selectionRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L10n.string(title))
                .font(AppFont.editorBody)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 92, alignment: .leading)
                .padding(.top, 6)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 29)
    }

    @ViewBuilder
    private var modelSelector: some View {
        switch session.speechProvider {
        case .googleCloud:
            Picker("Mô hình", selection: $session.googleModel) {
                ForEach(GoogleDubbingModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        case .maziao:
            Picker("Mô hình", selection: Binding(
                get: { session.maziaoModel },
                set: { session.selectMaziaoModel($0) }
            )) {
                ForEach(MaziaoDubbingModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        case .elevenLabs:
            Picker("Mô hình", selection: $session.elevenModel) {
                ForEach(ElevenLabsDubbingModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        case .appleOffline:
            Text(session.selectedModelLabel)
                .font(AppFont.editorBodyStrong)
                .foregroundStyle(AppTheme.bodyText)
        }
    }

    @ViewBuilder
    private var voiceSelector: some View {
        switch session.speechProvider {
        case .googleCloud:
            DubbingSearchableVoicePicker(
                selection: Binding(
                    get: { session.googleVoiceIdentifier },
                    set: { session.selectGoogleVoice($0) }
                ),
                voices: googleVoiceItems,
                isLoading: session.isRefreshingGoogleVoices,
                emptyTitle: "Chưa tải danh sách giọng",
                showsSyncSummary: !session.googleVoices.isEmpty
            )
        case .maziao:
            DubbingSearchableVoicePicker(
                selection: Binding(
                    get: { session.maziaoVoiceIdentifier },
                    set: { session.selectMaziaoVoice($0) }
                ),
                voices: maziaoVoiceItems,
                isLoading: session.isRefreshingMaziaoVoices,
                emptyTitle: "Chưa tải danh sách giọng",
                showsSyncSummary: !session.maziaoVoices.isEmpty
            )
        case .elevenLabs:
            VStack(alignment: .leading, spacing: 7) {
                DubbingSearchableVoicePicker(
                    selection: Binding(
                        get: { session.elevenVoiceIdentifier },
                        set: { session.selectElevenVoice($0) }
                    ),
                    voices: elevenVoiceItems,
                    isLoading: session.isRefreshingElevenVoices,
                    emptyTitle: "Chưa tải danh sách giọng",
                    showsSyncSummary: !session.elevenVoices.isEmpty
                )
                TextField(L10n.string("Hoặc nhập Voice ID thủ công"), text: $session.elevenVoiceIdentifier)
                    .textFieldStyle(.plain)
                    .font(AppFont.mono)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(AppFieldSurface(radius: AppTheme.editorControlRadius))
            }
        case .appleOffline:
            DubbingSearchableVoicePicker(
                selection: appleVoiceBinding,
                voices: appleVoiceItems,
                isLoading: false,
                emptyTitle: "Chưa chọn giọng",
                showsSyncSummary: false
            )
        }
    }

    private var appleVoiceOptions: [DubbingVoiceDescriptor] {
        session.voices.sorted {
            if $0.language == $1.language { return $0.name < $1.name }
            return $0.language < $1.language
        }
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { session.voiceIdentifier },
            set: { identifier in
                if let voice = session.voices.first(where: { $0.id == identifier }) {
                    session.languageIdentifier = voice.language
                }
                session.voiceIdentifier = identifier
            }
        )
    }

    private var googleVoiceItems: [DubbingVoiceCatalogItem] {
        session.googleVoicesForSelectedModel.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: DubbingVoiceCatalogPolicy.localizedGender($0.gender))
        }
    }

    private var maziaoVoiceItems: [DubbingVoiceCatalogItem] {
        session.maziaoVoicesForSelectedModel.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: DubbingVoiceCatalogPolicy.localizedGender($0.gender))
        }
    }

    private var elevenVoiceItems: [DubbingVoiceCatalogItem] {
        session.elevenVoices.map {
            let detail = [DubbingVoiceCatalogPolicy.localizedGender($0.gender), $0.category]
                .filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · ")
            return DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: detail)
        }
    }

    private var appleVoiceItems: [DubbingVoiceCatalogItem] {
        appleVoiceOptions.map {
            DubbingVoiceCatalogItem(id: $0.id, name: $0.name, language: $0.language, detail: $0.qualityLabel)
        }
    }

    private var selectedCatalogError: String {
        switch session.speechProvider {
        case .googleCloud: session.googleVoiceCatalogError
        case .maziao: session.maziaoVoiceCatalogError
        case .elevenLabs: session.elevenVoiceCatalogError
        case .appleOffline: ""
        }
    }

    private var voiceCatalogTaskID: String {
        "\(session.speechProvider.rawValue)|\(session.hasCredential(for: session.speechProvider))"
    }

    private func compactSliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        HStack(spacing: 9) {
            Text(L10n.string(title))
                .font(AppFont.editorBody)
                .foregroundStyle(AppTheme.bodyText)
                .frame(width: 92, alignment: .leading)
            SubtitleStyleGlassSlider(value: value, range: range)
                .frame(height: 22)
            Text(display)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 54, alignment: .trailing)
        }
        .frame(minHeight: 29)
    }

    private var normalizedRatePercent: Double {
        Double(session.speechRate / 0.5) * 100
    }

}

struct DubbingTimelineLane: NSViewRepresentable {
    @ObservedObject var session: DubbingSessionModel
    let pixelsPerSecond: Double
    let width: CGFloat
    let height: CGFloat
    let selectedIDs: Set<Int>
    let isDarkTheme: Bool
    let snapEnabled: Bool
    let snapTimes: [Double]
    let onSelect: (Int, TimelineCueSelectionIntent) -> Void
    let onMarqueeSelection: (Set<Int>) -> Void
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> DubbingTimelineLaneNSView {
        let view = DubbingTimelineLaneNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DubbingTimelineLaneNSView, context: Context) {
        view.cues = session.effectiveRenderedCues
        view.pixelsPerSecond = pixelsPerSecond
        view.selectedIDs = selectedIDs
        view.isDarkTheme = isDarkTheme
        view.snapEnabled = snapEnabled
        view.snapTimes = snapTimes
        view.onSelect = onSelect
        view.onMarqueeSelection = onMarqueeSelection
        view.onSeek = onSeek
        view.onRatePreview = session.previewPlaybackRates
        view.onRateCommit = session.commitPlaybackRateChanges
        view.onResetRate = session.resetPlaybackRate
        view.toolTip = L10n.string("Kéo đuôi DUB: dài hơn = chậm, ngắn hơn = nhanh; double-click để về 1×.")
        view.window?.invalidateCursorRects(for: view)
        view.needsDisplay = true
    }
}

final class DubbingTimelineLaneNSView: NSView {
    var cues: [DubbingRenderedCue] = []
    var pixelsPerSecond = 80.0
    var selectedIDs: Set<Int> = []
    var isDarkTheme = false
    var snapEnabled = true
    var snapTimes: [Double] = []
    var onSelect: ((Int, TimelineCueSelectionIntent) -> Void)?
    var onMarqueeSelection: ((Set<Int>) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onRatePreview: (([Int: Double]) -> Void)?
    var onRateCommit: ((Set<Int>) -> Void)?
    var onResetRate: ((Set<Int>) -> Void)?

    private enum DragMode { case none, select, stretch, marquee }
    private enum MarqueeMode { case replace, add, toggle }
    private var dragMode: DragMode = .none
    private var anchorCueID: Int?
    private var dragGroupIDs: Set<Int> = []
    private var downPoint: NSPoint = .zero
    private var initialDurations: [Int: Double] = [:]
    private var marqueeBand: NSRect?
    private var marqueePreviewIDs: Set<Int>?
    private var selectionAtMouseDown: Set<Int> = []
    private var marqueeMode: MarqueeMode = .replace
    private let edgeWidth: CGFloat = 10

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Clip DUB vẫn là một dải 40 px gọn. Phần trong suốt còn lại của bounds là
    /// vùng marquee rộng từ dưới AUDIO tới đáy Timeline.
    private var visualLaneBounds: NSRect {
        NSRect(x: 0, y: 0, width: bounds.width, height: min(40, bounds.height))
    }

    private func frame(for cue: DubbingRenderedCue) -> NSRect {
        let laneHeight = visualLaneBounds.height
        return NSRect(
            x: CGFloat(cue.startSeconds * pixelsPerSecond),
            y: 4,
            width: max(3, CGFloat(cue.playedDuration * pixelsPerSecond)),
            height: max(18, laneHeight - 8)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let visibleLane = visualLaneBounds.intersection(dirtyRect)
        if !visibleLane.isEmpty {
            laneBackground.setFill()
            visibleLane.fill()
        }
        let displayedSelection = marqueePreviewIDs ?? selectedIDs

        for cue in cues {
            let clipFrame = frame(for: cue)
            guard clipFrame.intersects(dirtyRect) else { continue }
            let selected = displayedSelection.contains(cue.id)
            let path = NSBezierPath(roundedRect: clipFrame, xRadius: 4, yRadius: 4)
            (cue.fit == .needsReview ? warningFill : readyFill).setFill()
            path.fill()
            if selected {
                NSColor.white.withAlphaComponent(0.92).setStroke()
                path.lineWidth = 1.35
                path.stroke()
            }

            let handle = NSRect(
                x: max(clipFrame.minX, clipFrame.maxX - edgeWidth),
                y: clipFrame.minY,
                width: min(edgeWidth, clipFrame.width),
                height: clipFrame.height
            )
            NSColor.white.withAlphaComponent(selected ? 0.26 : 0.14).setFill()
            handle.fill()
            NSColor.white.withAlphaComponent(selected ? 0.95 : 0.62).setStroke()
            let handleLine = NSBezierPath()
            handleLine.move(to: NSPoint(x: handle.midX, y: handle.minY + 6))
            handleLine.line(to: NSPoint(x: handle.midX, y: handle.maxY - 6))
            handleLine.lineWidth = selected ? 1.4 : 1
            handleLine.stroke()

            if clipFrame.width > 34 {
                let prefix = cue.fit == .needsReview ? "! " : ""
                let rate = abs(cue.playbackRate - 1) > 0.001 || selected
                    ? String(format: "%.2f×", cue.playbackRate)
                    : "DUB"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92)
                ]
                ((prefix + rate) as NSString).draw(
                    in: NSRect(x: clipFrame.minX + 5, y: clipFrame.midY - 6, width: max(1, clipFrame.width - 18), height: 13),
                    withAttributes: attributes
                )
            }
        }

        if let marqueeBand {
            marqueeColor.withAlphaComponent(0.15).setFill()
            marqueeBand.fill()
            marqueeColor.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: marqueeBand.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(downPoint) else {
            dragMode = .none
            return
        }
        selectionAtMouseDown = selectedIDs
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        marqueeMode = flags.contains(.command) ? .toggle : flags.contains(.shift) ? .add : .replace

        guard let cue = cues.reversed().first(where: { frame(for: $0).contains(downPoint) }) else {
            dragMode = .marquee
            marqueeBand = NSRect(origin: downPoint, size: CGSize(width: 1, height: 1))
            updateMarquee(to: downPoint)
            return
        }

        let clipFrame = frame(for: cue)
        let hitsHandle = downPoint.x >= clipFrame.maxX - min(edgeWidth, clipFrame.width)
        let independentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let preservesSelectedGroup = hitsHandle
            && selectedIDs.contains(cue.id)
            && !independentFlags.contains(.command)
            && !independentFlags.contains(.shift)
        if !preservesSelectedGroup {
            onSelect?(cue.id, .from(event.modifierFlags))
        }
        let group = selectedIDs.contains(cue.id)
            ? selectedIDs.intersection(cues.map(\.id))
            : Set([cue.id])
        if hitsHandle, event.clickCount >= 2 {
            onResetRate?(group)
            dragMode = .none
            return
        }
        guard hitsHandle else {
            dragMode = .select
            anchorCueID = cue.id
            return
        }

        dragMode = .stretch
        anchorCueID = cue.id
        dragGroupIDs = group
        initialDurations = Dictionary(uniqueKeysWithValues: cues
            .filter { group.contains($0.id) }
            .map { ($0.id, $0.playedDuration) })
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .stretch:
            guard let anchorCueID,
                  let anchor = cues.first(where: { $0.id == anchorCueID }),
                  let initialAnchorDuration = initialDurations[anchorCueID],
                  initialAnchorDuration > 0 else { return }
            let delta = Double(point.x - downPoint.x) / pixelsPerSecond
            let minimumDuration = anchor.audioDuration / DubbingRenderedCue.maximumPlaybackRate
            let maximumDuration = anchor.audioDuration / DubbingRenderedCue.minimumPlaybackRate
            var targetDuration = min(maximumDuration, max(minimumDuration, initialAnchorDuration + delta))
            if snapEnabled,
               let nearest = snapTimes.min(by: {
                   abs($0 - (anchor.startSeconds + targetDuration))
                       < abs($1 - (anchor.startSeconds + targetDuration))
               }),
               abs(nearest - (anchor.startSeconds + targetDuration)) * pixelsPerSecond <= 8 {
                targetDuration = min(maximumDuration, max(minimumDuration, nearest - anchor.startSeconds))
            }
            let durationScale = targetDuration / initialAnchorDuration
            var rates: [Int: Double] = [:]
            for cue in cues where dragGroupIDs.contains(cue.id) {
                guard let initialDuration = initialDurations[cue.id], initialDuration > 0 else { continue }
                let playedDuration = initialDuration * durationScale
                rates[cue.id] = cue.audioDuration / playedDuration
            }
            onRatePreview?(rates)
        case .marquee:
            updateMarquee(to: point)
        case .none, .select:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = .none
            anchorCueID = nil
            dragGroupIDs = []
            initialDurations = [:]
            marqueeBand = nil
            marqueePreviewIDs = nil
            NSCursor.arrow.set()
            needsDisplay = true
        }
        switch dragMode {
        case .stretch:
            onRateCommit?(dragGroupIDs)
        case .select:
            if let cueID = anchorCueID, let cue = cues.first(where: { $0.id == cueID }) {
                onSeek?(cue.startSeconds)
            }
        case .marquee:
            onMarqueeSelection?(marqueePreviewIDs ?? [])
        case .none:
            break
        }
    }

    private func updateMarquee(to point: NSPoint) {
        let activeBounds = bounds
        let clipped = NSPoint(
            x: min(max(point.x, activeBounds.minX), activeBounds.maxX),
            y: min(max(point.y, activeBounds.minY), activeBounds.maxY)
        )
        marqueeBand = NSRect(
            x: min(downPoint.x, clipped.x),
            y: min(downPoint.y, clipped.y),
            width: max(1, abs(clipped.x - downPoint.x)),
            height: max(1, abs(clipped.y - downPoint.y))
        )
        // DUB chỉ có một lane: khoảng chọn theo trục thời gian (X), nên user có
        // thể bắt đầu quét ở vùng trống dưới clip mà không phải chạm đúng dải 40 px.
        let selectionX = (marqueeBand ?? .zero).minX...(marqueeBand ?? .zero).maxX
        let hits = Set(cues.filter {
            let cueFrame = frame(for: $0)
            return cueFrame.maxX >= selectionX.lowerBound && cueFrame.minX <= selectionX.upperBound
        }.map(\.id))
        switch marqueeMode {
        case .replace: marqueePreviewIDs = hits
        case .add: marqueePreviewIDs = selectionAtMouseDown.union(hits)
        case .toggle: marqueePreviewIDs = selectionAtMouseDown.symmetricDifference(hits)
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for cue in cues {
            let clipFrame = frame(for: cue)
            let handle = NSRect(
                x: max(clipFrame.minX, clipFrame.maxX - edgeWidth),
                y: clipFrame.minY,
                width: min(edgeWidth, clipFrame.width),
                height: clipFrame.height
            )
            addCursorRect(handle, cursor: .resizeLeftRight)
        }
    }

    private var laneBackground: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.035, green: 0.09, blue: 0.14, alpha: 1)
            : NSColor(srgbRed: 0.75, green: 0.83, blue: 0.91, alpha: 1)
    }
    private var readyFill: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.10, green: 0.43, blue: 0.36, alpha: 0.95)
            : NSColor(srgbRed: 0.08, green: 0.55, blue: 0.39, alpha: 0.84)
    }
    private var warningFill: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.76, green: 0.37, blue: 0.10, alpha: 0.96)
            : NSColor(srgbRed: 0.91, green: 0.43, blue: 0.08, alpha: 0.88)
    }
    private var marqueeColor: NSColor { NSColor.systemTeal }
}
