import AppKit
import SwiftUI

enum WorkspaceSplitAxis {
    case vertical
    case horizontal
}

private enum WorkspaceEditActiveDrag {
    case topColumns
    case rowHeights
    case transcriptLeft
    case transcriptRight
}

struct WorkspaceLayoutMetrics {
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let topRowHeight: CGFloat
    let bottomRowHeight: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
}

/// Lưới 2×2 kéo co — chỉ UI, lưu tỉ lệ UserDefaults, không đụng engine.
struct WorkspaceResizableChessboard<TL: View, TR: View, BL: View, BR: View>: View {
    let storageKey: String
    @Binding var leftColumnWidth: CGFloat

    var columnGap: CGFloat = AppTheme.workspaceColumnGap
    var rowGap: CGFloat = AppTheme.workspaceRowGap
    var handleHitBreadth: CGFloat = 10
    var minCellWidth: CGFloat = 240
    var minCellHeight: CGFloat = 140
    var defaultLeftWidth: CGFloat = 380
    var defaultTopRowRatio: CGFloat = 0.48

    @ViewBuilder var topLeft: (WorkspaceLayoutMetrics) -> TL
    @ViewBuilder var topRight: (WorkspaceLayoutMetrics) -> TR
    @ViewBuilder var bottomLeft: (WorkspaceLayoutMetrics) -> BL
    @ViewBuilder var bottomRight: (WorkspaceLayoutMetrics) -> BR

    @State private var topRowRatio: CGFloat
    @State private var leftColumnRatio: CGFloat
    @State private var activeDrag: WorkspaceSplitAxis?
    @State private var dragOriginLeft: CGFloat = 0
    @State private var dragOriginTopRatio: CGFloat = 0.48
    @State private var didLoadLayout = false

    init(
        storageKey: String,
        leftColumnWidth: Binding<CGFloat>,
        columnGap: CGFloat = AppTheme.workspaceColumnGap,
        rowGap: CGFloat = AppTheme.workspaceRowGap,
        handleHitBreadth: CGFloat = 10,
        minCellWidth: CGFloat = 240,
        minCellHeight: CGFloat = 140,
        defaultLeftWidth: CGFloat = 380,
        defaultTopRowRatio: CGFloat = 0.48,
        @ViewBuilder topLeft: @escaping (WorkspaceLayoutMetrics) -> TL,
        @ViewBuilder topRight: @escaping (WorkspaceLayoutMetrics) -> TR,
        @ViewBuilder bottomLeft: @escaping (WorkspaceLayoutMetrics) -> BL,
        @ViewBuilder bottomRight: @escaping (WorkspaceLayoutMetrics) -> BR
    ) {
        self.storageKey = storageKey
        self._leftColumnWidth = leftColumnWidth
        self.columnGap = columnGap
        self.rowGap = rowGap
        self.handleHitBreadth = handleHitBreadth
        self.minCellWidth = minCellWidth
        self.minCellHeight = minCellHeight
        self.defaultLeftWidth = defaultLeftWidth
        self.defaultTopRowRatio = defaultTopRowRatio
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight

        let seed = Self.seedLayoutState(
            storageKey: storageKey,
            columnGap: columnGap,
            minCellWidth: minCellWidth,
            defaultLeftWidth: defaultLeftWidth,
            defaultTopRowRatio: defaultTopRowRatio
        )
        _leftColumnRatio = State(initialValue: seed.leftRatio)
        _topRowRatio = State(initialValue: seed.topRatio)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentSize = geometry.size
            let metrics = resolvedMetrics(in: contentSize)

            ZStack(alignment: .topLeading) {
                grid(metrics: metrics)
                splitHandles(metrics: metrics, contentSize: contentSize)
            }
            .onAppear {
                syncLayoutFromStorage(containerWidth: contentSize.width)
                applyMetricsToBinding(metrics)
            }
            .onChange(of: geometry.size) { _, newSize in
                syncLayoutFromStorage(containerWidth: newSize.width)
                if !activeDragActive {
                    applyMetricsToBinding(resolvedMetrics(in: newSize))
                }
            }
        }
    }

    private var activeDragActive: Bool { activeDrag != nil }

    private func resolvedMetrics(in size: CGSize) -> WorkspaceLayoutMetrics {
        let contentW = max(0, size.width)
        let contentH = max(0, size.height)
        let trackW = max(0, contentW - columnGap)
        let trackH = max(0, contentH - rowGap)

        let minLeft = min(minCellWidth, max(0, trackW - minCellWidth))
        let maxLeft = max(minLeft, trackW - minCellWidth)
        let leftW = min(max(trackW * leftColumnRatio, minLeft), maxLeft)

        let minTop = min(minCellHeight, max(0, trackH - minCellHeight))
        let maxTop = max(minTop, trackH - minCellHeight)
        let topH = min(max(trackH * topRowRatio, minTop), maxTop)

        return WorkspaceLayoutMetrics(
            leftWidth: floor(leftW),
            rightWidth: floor(trackW - leftW),
            topRowHeight: floor(topH),
            bottomRowHeight: floor(trackH - topH),
            columnGap: columnGap,
            rowGap: rowGap
        )
    }

    @ViewBuilder
    private func grid(metrics: WorkspaceLayoutMetrics) -> some View {
        VStack(spacing: metrics.rowGap) {
            HStack(spacing: metrics.columnGap) {
                topLeft(metrics)
                    .frame(width: metrics.leftWidth, height: metrics.topRowHeight, alignment: .topLeading)
                topRight(metrics)
                    .frame(width: metrics.rightWidth, height: metrics.topRowHeight, alignment: .topLeading)
            }
            HStack(spacing: metrics.columnGap) {
                bottomLeft(metrics)
                    .frame(width: metrics.leftWidth, height: metrics.bottomRowHeight, alignment: .topLeading)
                bottomRight(metrics)
                    .frame(width: metrics.rightWidth, height: metrics.bottomRowHeight, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func splitHandles(metrics: WorkspaceLayoutMetrics, contentSize: CGSize) -> some View {
        let verticalX = metrics.leftWidth + metrics.columnGap / 2
        let horizontalY = metrics.topRowHeight + metrics.rowGap / 2

        WorkspaceSplitHandle(axis: .vertical, isDragging: activeDrag == .vertical)
            .frame(width: max(handleHitBreadth, metrics.columnGap), height: contentSize.height)
            .contentShape(Rectangle())
            .position(x: verticalX, y: contentSize.height / 2)
            .gesture(verticalDragGesture(containerWidth: contentSize.width))

        WorkspaceSplitHandle(axis: .horizontal, isDragging: activeDrag == .horizontal)
            .frame(width: contentSize.width, height: max(handleHitBreadth, metrics.rowGap))
            .contentShape(Rectangle())
            .position(x: contentSize.width / 2, y: horizontalY)
            .gesture(horizontalDragGesture(containerHeight: contentSize.height))
    }

    private func verticalDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .vertical {
                    activeDrag = .vertical
                    dragOriginLeft = leftColumnRatio
                }
                let trackW = max(1, containerWidth - columnGap)
                let minLeft = min(minCellWidth, max(0, trackW - minCellWidth))
                let maxLeft = max(minLeft, trackW - minCellWidth)
                let proposed = dragOriginLeft * trackW + value.translation.width
                let clamped = min(max(proposed, minLeft), maxLeft)
                leftColumnRatio = clamped / trackW
                leftColumnWidth = floor(clamped)
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func horizontalDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .horizontal {
                    activeDrag = .horizontal
                    dragOriginTopRatio = topRowRatio
                }
                let trackH = max(1, containerHeight - rowGap)
                let minTop = min(minCellHeight, max(0, trackH - minCellHeight))
                let maxTop = max(minTop, trackH - minCellHeight)
                let proposed = dragOriginTopRatio * trackH + value.translation.height
                let clamped = min(max(proposed, minTop), maxTop)
                topRowRatio = clamped / trackH
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func syncLayoutFromStorage(containerWidth: CGFloat) {
        guard !activeDragActive else { return }
        let trackW = max(1, containerWidth - columnGap)
        guard trackW > 200 else { return }

        let defaults = UserDefaults.standard
        let hasPinnedLeftWidth = defaults.object(forKey: "\(storageKey).leftWidth") != nil
        if hasPinnedLeftWidth || !didLoadLayout {
            applyStoredLeftWidth(trackW: trackW, defaults: defaults)
            if defaults.object(forKey: "\(storageKey).topRatio") != nil {
                topRowRatio = CGFloat(defaults.double(forKey: "\(storageKey).topRatio"))
            } else if !didLoadLayout {
                topRowRatio = defaultTopRowRatio
            }
            didLoadLayout = true
        }
    }

    private func applyStoredLeftWidth(trackW: CGFloat, defaults: UserDefaults) {
        let minLeft = min(minCellWidth, max(0, trackW - minCellWidth))
        let maxLeft = max(minLeft, trackW - minCellWidth)

        let targetWidth: CGFloat
        if defaults.object(forKey: "\(storageKey).leftWidth") != nil {
            targetWidth = CGFloat(defaults.double(forKey: "\(storageKey).leftWidth"))
        } else if defaults.object(forKey: "\(storageKey).leftRatio") != nil {
            let legacyRatio = CGFloat(defaults.double(forKey: "\(storageKey).leftRatio"))
            targetWidth = legacyRatio * trackW
        } else {
            targetWidth = defaultLeftWidth
        }

        let clamped = min(max(targetWidth, minLeft), maxLeft)
        leftColumnRatio = clamped / trackW
    }

    private func persistLayout() {
        let defaults = UserDefaults.standard
        defaults.set(Double(leftColumnWidth), forKey: "\(storageKey).leftWidth")
        defaults.removeObject(forKey: "\(storageKey).leftRatio")
        defaults.set(Double(topRowRatio), forKey: "\(storageKey).topRatio")
    }

    private static func seedLayoutState(
        storageKey: String,
        columnGap: CGFloat,
        minCellWidth: CGFloat,
        defaultLeftWidth: CGFloat,
        defaultTopRowRatio: CGFloat
    ) -> (leftRatio: CGFloat, topRatio: CGFloat) {
        let defaults = UserDefaults.standard
        let referenceTrackW: CGFloat = 1100
        let minLeft = min(minCellWidth, max(0, referenceTrackW - minCellWidth))
        let maxLeft = max(minLeft, referenceTrackW - minCellWidth)

        let targetWidth: CGFloat
        if defaults.object(forKey: "\(storageKey).leftWidth") != nil {
            targetWidth = CGFloat(defaults.double(forKey: "\(storageKey).leftWidth"))
        } else if defaults.object(forKey: "\(storageKey).leftRatio") != nil {
            targetWidth = CGFloat(defaults.double(forKey: "\(storageKey).leftRatio")) * referenceTrackW
        } else {
            targetWidth = defaultLeftWidth
        }
        let clamped = min(max(targetWidth, minLeft), maxLeft)

        let topRatio: CGFloat
        if defaults.object(forKey: "\(storageKey).topRatio") != nil {
            topRatio = CGFloat(defaults.double(forKey: "\(storageKey).topRatio"))
        } else {
            topRatio = defaultTopRowRatio
        }
        return (clamped / referenceTrackW, topRatio)
    }

    private func applyMetricsToBinding(_ metrics: WorkspaceLayoutMetrics) {
        leftColumnWidth = metrics.leftWidth
    }
}

// MARK: - Chỉnh sửa sub: hàng trên riêng + transcript dưới tự do (không link cột trên)

struct WorkspaceEditLayoutMetrics {
    let leftColumnWidth: CGFloat
    let burnWidth: CGFloat
    let topRowHeight: CGFloat
    let transcriptHeight: CGFloat
    let transcriptWidth: CGFloat
    let transcriptLeading: CGFloat
    let totalWidth: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
}

struct WorkspaceResizableEditLayout<Preview: View, Burn: View, Transcript: View>: View {
    let storageKey: String
    @Binding var leftColumnWidth: CGFloat
    @Binding var dockTranscriptLeading: CGFloat
    @Binding var dockTranscriptWidth: CGFloat

    var columnGap: CGFloat = AppTheme.workspaceColumnGap
    var rowGap: CGFloat = AppTheme.workspaceRowGap
    var handleHitBreadth: CGFloat = 14
    var defaultLeftWidth: CGFloat = 380
    var defaultTopRowRatio: CGFloat = 0.48
    var minLeftColumnWidth: CGFloat = 240
    var minBurnWidth: CGFloat = 240
    var minTopRowHeight: CGFloat = 160
    var minTranscriptHeight: CGFloat = 140
    var minTranscriptWidth: CGFloat = 320

    @ViewBuilder var preview: (_ metrics: WorkspaceEditLayoutMetrics) -> Preview
    @ViewBuilder var burn: (_ metrics: WorkspaceEditLayoutMetrics) -> Burn
    @ViewBuilder var transcript: (_ metrics: WorkspaceEditLayoutMetrics) -> Transcript

    @State private var topRowRatio: CGFloat = 0.48
    @State private var burnColumnWidth: CGFloat = 340
    @State private var transcriptLeading: CGFloat = 0
    @State private var transcriptWidth: CGFloat = 720
    @State private var activeDrag: WorkspaceEditActiveDrag?
    @State private var dragOriginBurnWidth: CGFloat = 340
    @State private var dragOriginTopRatio: CGFloat = 0.48
    @State private var dragOriginTranscriptLeading: CGFloat = 0
    @State private var dragOriginTranscriptWidth: CGFloat = 720
    @State private var didLoadLayout = false

    var body: some View {
        GeometryReader { geometry in
            let contentSize = geometry.size
            let metrics = resolvedMetrics(in: contentSize)

            ZStack(alignment: .topLeading) {
                grid(metrics: metrics)
                splitHandles(metrics: metrics, contentSize: contentSize)
                    .zIndex(20)
            }
            .onAppear {
                loadLayoutIfNeeded(containerWidth: contentSize.width)
                applyLeftColumnBinding(metrics)
            }
            .onChange(of: geometry.size) { _, newSize in
                clampTranscriptFrame(containerWidth: newSize.width)
                if !activeDragActive {
                    applyLeftColumnBinding(resolvedMetrics(in: newSize))
                }
            }
        }
    }

    private var activeDragActive: Bool { activeDrag != nil }

    private func resolvedMetrics(in size: CGSize) -> WorkspaceEditLayoutMetrics {
        let totalW = max(0, size.width)
        let totalH = max(0, size.height)
        let trackW = max(0, totalW - columnGap)
        let trackH = max(0, totalH - rowGap)

        let minBurn = min(minBurnWidth, max(0, trackW - minLeftColumnWidth))
        let maxBurn = max(minBurn, trackW - minLeftColumnWidth)
        let burnW = min(max(burnColumnWidth, minBurn), maxBurn)
        let leftW = max(minLeftColumnWidth, trackW - burnW)

        let minTop = min(minTopRowHeight, max(0, trackH - minTranscriptHeight))
        let maxTop = max(minTop, trackH - minTranscriptHeight)
        let topH = min(max(trackH * topRowRatio, minTop), maxTop)
        let bottomH = max(minTranscriptHeight, trackH - topH)
        let clampedTranscript = clampedTranscriptFrame(totalWidth: totalW)

        return WorkspaceEditLayoutMetrics(
            leftColumnWidth: floor(leftW),
            burnWidth: floor(burnW),
            topRowHeight: floor(topH),
            transcriptHeight: floor(bottomH),
            transcriptWidth: floor(clampedTranscript.width),
            transcriptLeading: floor(clampedTranscript.leading),
            totalWidth: floor(totalW),
            columnGap: columnGap,
            rowGap: rowGap
        )
    }

    private func clampedTranscriptFrame(totalWidth: CGFloat) -> (leading: CGFloat, width: CGFloat) {
        let maxWidth = max(minTranscriptWidth, totalWidth)
        let width = min(max(transcriptWidth, minTranscriptWidth), maxWidth)
        let maxLeading = max(0, totalWidth - width)
        let leading = min(max(transcriptLeading, 0), maxLeading)
        return (leading, width)
    }

    private func clampTranscriptFrame(containerWidth: CGFloat) {
        let clamped = clampedTranscriptFrame(totalWidth: containerWidth)
        transcriptLeading = clamped.leading
        transcriptWidth = clamped.width
    }

    @ViewBuilder
    private func grid(metrics: WorkspaceEditLayoutMetrics) -> some View {
        VStack(spacing: metrics.rowGap) {
            HStack(spacing: metrics.columnGap) {
                preview(metrics)
                    .frame(width: metrics.leftColumnWidth, height: metrics.topRowHeight, alignment: .topLeading)
                burn(metrics)
                    .frame(width: metrics.burnWidth, height: metrics.topRowHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            transcript(metrics)
                .frame(width: metrics.transcriptWidth, height: metrics.transcriptHeight, alignment: .topLeading)
                .offset(x: metrics.transcriptLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func splitHandles(metrics: WorkspaceEditLayoutMetrics, contentSize: CGSize) -> some View {
        let columnSplitX = metrics.leftColumnWidth + metrics.columnGap / 2
        let rowSplitY = metrics.topRowHeight + metrics.rowGap / 2
        let transcriptMidY = metrics.topRowHeight + metrics.rowGap + metrics.transcriptHeight / 2
        let transcriptLeftX = metrics.transcriptLeading
        let transcriptRightX = metrics.transcriptLeading + metrics.transcriptWidth

        WorkspaceSplitHandle(axis: .vertical, isDragging: activeDrag == .topColumns)
            .frame(width: max(handleHitBreadth, metrics.columnGap), height: metrics.topRowHeight)
            .contentShape(Rectangle())
            .position(x: columnSplitX, y: metrics.topRowHeight / 2)
            .gesture(columnSplitDragGesture(containerWidth: contentSize.width))

        WorkspaceSplitHandle(axis: .horizontal, isDragging: activeDrag == .rowHeights)
            .frame(width: contentSize.width, height: max(handleHitBreadth, metrics.rowGap))
            .contentShape(Rectangle())
            .position(x: contentSize.width / 2, y: rowSplitY)
            .gesture(rowSplitDragGesture(containerHeight: contentSize.height))

        WorkspaceSplitHandle(axis: .vertical, isDragging: activeDrag == .transcriptLeft)
            .frame(width: handleHitBreadth, height: metrics.transcriptHeight)
            .contentShape(Rectangle())
            .position(x: transcriptLeftX, y: transcriptMidY)
            .gesture(transcriptLeftDragGesture(containerWidth: contentSize.width))

        WorkspaceSplitHandle(axis: .vertical, isDragging: activeDrag == .transcriptRight)
            .frame(width: handleHitBreadth, height: metrics.transcriptHeight)
            .contentShape(Rectangle())
            .position(x: transcriptRightX, y: transcriptMidY)
            .gesture(transcriptRightDragGesture(containerWidth: contentSize.width))
    }

    private func columnSplitDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .topColumns {
                    activeDrag = .topColumns
                    dragOriginBurnWidth = burnColumnWidth
                }
                let trackW = max(1, containerWidth - columnGap)
                let minBurn = min(minBurnWidth, max(0, trackW - minLeftColumnWidth))
                let maxBurn = max(minBurn, trackW - minLeftColumnWidth)
                let proposed = dragOriginBurnWidth - value.translation.width
                burnColumnWidth = min(max(proposed, minBurn), maxBurn)
                leftColumnWidth = floor(max(minLeftColumnWidth, trackW - burnColumnWidth))
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func rowSplitDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .rowHeights {
                    activeDrag = .rowHeights
                    dragOriginTopRatio = topRowRatio
                }
                let trackH = max(1, containerHeight - rowGap)
                let minTop = min(minTopRowHeight, max(0, trackH - minTranscriptHeight))
                let maxTop = max(minTop, trackH - minTranscriptHeight)
                let proposed = dragOriginTopRatio * trackH + value.translation.height
                let clamped = min(max(proposed, minTop), maxTop)
                topRowRatio = clamped / trackH
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func transcriptLeftDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .transcriptLeft {
                    activeDrag = .transcriptLeft
                    dragOriginTranscriptLeading = transcriptLeading
                    dragOriginTranscriptWidth = transcriptWidth
                }
                let proposedLeading = dragOriginTranscriptLeading + value.translation.width
                let proposedWidth = dragOriginTranscriptWidth - value.translation.width
                let width = min(max(proposedWidth, minTranscriptWidth), containerWidth)
                let leading = min(max(proposedLeading, 0), containerWidth - width)
                transcriptWidth = width
                transcriptLeading = leading
                syncDockTranscriptBindings(totalWidth: containerWidth)
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func transcriptRightDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeDrag != .transcriptRight {
                    activeDrag = .transcriptRight
                    dragOriginTranscriptWidth = transcriptWidth
                }
                let proposedWidth = dragOriginTranscriptWidth + value.translation.width
                let maxWidth = containerWidth - transcriptLeading
                transcriptWidth = min(max(proposedWidth, minTranscriptWidth), maxWidth)
                syncDockTranscriptBindings(totalWidth: containerWidth)
            }
            .onEnded { _ in
                activeDrag = nil
                persistLayout()
            }
    }

    private func syncDockTranscriptBindings(totalWidth: CGFloat) {
        let clamped = clampedTranscriptFrame(totalWidth: totalWidth)
        dockTranscriptLeading = floor(clamped.leading)
        dockTranscriptWidth = floor(clamped.width)
    }

    private func loadLayoutIfNeeded(containerWidth: CGFloat) {
        guard !didLoadLayout else { return }
        let defaults = UserDefaults.standard
        let trackW = max(1, containerWidth - columnGap)

        if defaults.object(forKey: "\(storageKey).burnWidth") != nil {
            burnColumnWidth = CGFloat(defaults.double(forKey: "\(storageKey).burnWidth"))
        } else {
            burnColumnWidth = max(minBurnWidth, trackW - defaultLeftWidth)
        }
        if defaults.object(forKey: "\(storageKey).topRatio") != nil {
            topRowRatio = CGFloat(defaults.double(forKey: "\(storageKey).topRatio"))
        } else if defaults.object(forKey: "\(storageKey).previewRatio") != nil {
            topRowRatio = CGFloat(defaults.double(forKey: "\(storageKey).previewRatio"))
        } else if defaults.object(forKey: "\(storageKey).leftRatio") != nil {
            _ = CGFloat(defaults.double(forKey: "\(storageKey).leftRatio"))
            topRowRatio = defaultTopRowRatio
        } else {
            topRowRatio = defaultTopRowRatio
        }
        if defaults.object(forKey: "\(storageKey).transcriptLeading") != nil {
            transcriptLeading = CGFloat(defaults.double(forKey: "\(storageKey).transcriptLeading"))
        }
        if defaults.object(forKey: "\(storageKey).transcriptWidth") != nil {
            transcriptWidth = CGFloat(defaults.double(forKey: "\(storageKey).transcriptWidth"))
        } else {
            transcriptWidth = containerWidth
            transcriptLeading = 0
        }
        clampTranscriptFrame(containerWidth: containerWidth)
        didLoadLayout = true
    }

    private func persistLayout() {
        let defaults = UserDefaults.standard
        defaults.set(Double(burnColumnWidth), forKey: "\(storageKey).burnWidth")
        defaults.set(Double(topRowRatio), forKey: "\(storageKey).topRatio")
        defaults.set(Double(transcriptLeading), forKey: "\(storageKey).transcriptLeading")
        defaults.set(Double(transcriptWidth), forKey: "\(storageKey).transcriptWidth")
    }

    private func applyLeftColumnBinding(_ metrics: WorkspaceEditLayoutMetrics) {
        leftColumnWidth = metrics.leftColumnWidth
        dockTranscriptLeading = metrics.transcriptLeading
        dockTranscriptWidth = metrics.transcriptWidth
    }
}

// MARK: - Vùng kéo vô hình + con trỏ resize

private struct WorkspaceSplitHandle: View {
    let axis: WorkspaceSplitAxis
    let isDragging: Bool

    var body: some View {
        Color.clear
            .onHover { hovering in
                applyCursor(active: hovering || isDragging)
            }
            .onChange(of: isDragging) { _, dragging in
                applyCursor(active: dragging)
            }
    }

    private func applyCursor(active: Bool) {
        if active {
            switch axis {
            case .vertical:
                NSCursor.resizeLeftRight.set()
            case .horizontal:
                NSCursor.resizeUpDown.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }
}