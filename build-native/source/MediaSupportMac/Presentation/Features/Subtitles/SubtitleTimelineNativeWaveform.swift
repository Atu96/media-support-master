import AppKit
import QuartzCore
import SwiftUI

/// Renderer native cho track audio dài. CATiledLayer chỉ gọi draw cho tile đang
/// lộ ra trong ScrollView; playhead là layer/view khác nên không làm vẽ lại sóng.
struct SubtitleTimelineNativeWaveform: NSViewRepresentable, Equatable {
    let peaks: [Float]
    let width: CGFloat
    let height: CGFloat
    let contentID: UUID
    let isDarkTheme: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.contentID == rhs.contentID && lhs.isDarkTheme == rhs.isDarkTheme
    }

    func makeNSView(context: Context) -> TimelineWaveformHostView {
        let view = TimelineWaveformHostView()
        view.configure(peaks: peaks, contentID: contentID, isDarkTheme: isDarkTheme)
        return view
    }

    func updateNSView(_ view: TimelineWaveformHostView, context: Context) {
        view.configure(peaks: peaks, contentID: contentID, isDarkTheme: isDarkTheme)
    }
}

final class TimelineWaveformHostView: NSView {
    override var isFlipped: Bool { true }
    private var appliedContentID: UUID?
    private var appliedIsDarkTheme: Bool?

    private var waveformLayer: TimelineWaveformTiledLayer {
        guard let layer = layer as? TimelineWaveformTiledLayer else {
            fatalError("Timeline waveform requires TimelineWaveformTiledLayer")
        }
        return layer
    }

    override func makeBackingLayer() -> CALayer {
        TimelineWaveformTiledLayer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    func configure(peaks: [Float], contentID: UUID, isDarkTheme: Bool) {
        let themeChanged = appliedIsDarkTheme != isDarkTheme
        guard appliedContentID != contentID || themeChanged else { return }
        appliedContentID = contentID
        appliedIsDarkTheme = isDarkTheme
        waveformLayer.setDarkTheme(isDarkTheme)
        waveformLayer.replacePeaks(peaks)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        waveformLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}

private final class TimelineWaveformTiledLayer: CATiledLayer {
    /// Không mutate array sau khi thay snapshot; các tile background có thể dùng snapshot cũ an toàn.
    private var peakSnapshot: [Float] = []
    private let peakSnapshotLock = NSLock()
    private var isDarkTheme = true

    override init() {
        super.init()
        tileSize = CGSize(width: 768, height: 70)
        levelsOfDetail = 1
        levelsOfDetailBias = 0
        backgroundColor = NSColor(calibratedRed: 0.055, green: 0.090, blue: 0.140, alpha: 1).cgColor
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tileSize = CGSize(width: 768, height: 70)
        levelsOfDetail = 1
        levelsOfDetailBias = 0
    }

    func replacePeaks(_ peaks: [Float]) {
        peakSnapshotLock.lock()
        peakSnapshot = peaks
        peakSnapshotLock.unlock()
        setNeedsDisplay()
    }

    func setDarkTheme(_ isDarkTheme: Bool) {
        self.isDarkTheme = isDarkTheme
        backgroundColor = background.cgColor
        setNeedsDisplay()
    }

    override func draw(in context: CGContext) {
        let drawingBounds = bounds
        context.setFillColor(background.cgColor)
        context.fill(context.boundingBoxOfClipPath)

        peakSnapshotLock.lock()
        let peaks = peakSnapshot
        peakSnapshotLock.unlock()
        guard !peaks.isEmpty,
              drawingBounds.width.isFinite, drawingBounds.height.isFinite,
              drawingBounds.width > 1, drawingBounds.height > 1 else {
            context.setStrokeColor(centerLine.cgColor)
            context.setLineWidth(0.6)
            context.move(to: CGPoint(x: 0, y: drawingBounds.midY))
            context.addLine(to: CGPoint(x: drawingBounds.width, y: drawingBounds.midY))
            context.strokePath()
            return
        }

        let clip = context.boundingBoxOfClipPath.intersection(drawingBounds)
        guard clip.minX.isFinite, clip.maxX.isFinite, clip.width.isFinite,
              clip.minX >= 0, clip.width > 0 else { return }
        let startColumn = max(0, Int(floor(clip.minX)))
        // CATiledLayer đôi lúc gửi clip rect bất thường ngay lúc đổi zoom cực
        // thấp. Mỗi tile chỉ cần tối đa 768px; cap 2.048 cột tránh cấp phát mảng
        // khổng lồ/crash mà vẫn phủ hoàn toàn tile đang thấy.
        let safeClipEnd = min(clip.maxX, clip.minX + 2_048)
        let endColumn = min(
            Int(min(drawingBounds.width, CGFloat(Int.max / 4))),
            max(startColumn + 1, Int(ceil(safeClipEnd)))
        )
        guard endColumn > startColumn else { return }

        // Một lane mono đối xứng quanh trục giữa cho cân với track sub. Đây không
        // phải hai kênh L/R: cùng một peak được phản chiếu lên/xuống.
        let centerY = drawingBounds.midY
        var upperPoints: [CGPoint] = []
        var lowerPoints: [CGPoint] = []
        upperPoints.reserveCapacity(endColumn - startColumn)
        lowerPoints.reserveCapacity(endColumn - startColumn)
        for column in startColumn..<endColumn {
            let start = Int(Double(column) * Double(peaks.count) / Double(drawingBounds.width))
            let end = min(peaks.count, max(start + 1, Int(Double(column + 1) * Double(peaks.count) / Double(drawingBounds.width))))
            var peak: Float = 0
            for index in start..<end { peak = max(peak, peaks[index]) }
            let amplitude = max(0.7, CGFloat(peak) * drawingBounds.height * 0.43)
            upperPoints.append(CGPoint(x: CGFloat(column), y: max(1, centerY - amplitude)))
            lowerPoints.append(CGPoint(x: CGFloat(column), y: min(drawingBounds.height - 1, centerY + amplitude)))
        }

        guard let firstUpper = upperPoints.first else { return }
        let fill = CGMutablePath()
        fill.move(to: firstUpper)
        for point in upperPoints.dropFirst() { fill.addLine(to: point) }
        for point in lowerPoints.reversed() { fill.addLine(to: point) }
        fill.closeSubpath()
        context.addPath(fill)
        context.setFillColor(waveFill.cgColor)
        context.fillPath()

        let upperContour = CGMutablePath()
        upperContour.addLines(between: upperPoints)
        let lowerContour = CGMutablePath()
        lowerContour.addLines(between: lowerPoints)
        context.addPath(upperContour)
        context.addPath(lowerContour)
        context.setStrokeColor(waveStroke.cgColor)
        context.setLineWidth(0.55)
        context.strokePath()

        context.setStrokeColor(centerLine.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: clip.minX, y: centerY))
        context.addLine(to: CGPoint(x: min(clip.maxX, safeClipEnd), y: centerY))
        context.strokePath()
    }

    private var background: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.055, green: 0.090, blue: 0.140, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.80, blue: 0.89, alpha: 1)
    }

    private var waveFill: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.30, green: 0.62, blue: 0.76, alpha: 0.72)
            : NSColor(srgbRed: 0.04, green: 0.37, blue: 0.62, alpha: 0.72)
    }

    private var waveStroke: NSColor {
        isDarkTheme ? NSColor.white.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.36)
    }

    private var centerLine: NSColor {
        isDarkTheme ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.14)
    }
}
