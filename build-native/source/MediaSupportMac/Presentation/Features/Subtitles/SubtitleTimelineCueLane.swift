import AppKit
import SwiftUI

extension TimelineCueSelectionIntent {
    static func from(_ modifiers: NSEvent.ModifierFlags) -> Self {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) { return .range }
        if flags.contains(.command) { return .toggle }
        return .replace
    }
}

/// Track cue AppKit: drag ổn định hơn gesture SwiftUI; kéo giữa=dời, mép=trim.
struct SubtitleTimelineCueLane: NSViewRepresentable {
    let segments: [SRTSegment]
    let pixelsPerSecond: Double
    let selectedIDs: Set<Int>
    let primarySelectedID: Int?
    /// Tâm dọc của dải cue trong toàn canvas. Canvas vẫn cao để marquee thoải mái.
    let cueTrackCenterY: CGFloat?
    let isDarkTheme: Bool
    let onSelect: (Int, TimelineCueSelectionIntent) -> Void
    let onMarqueeSelection: (Set<Int>) -> Void
    let onClearSelection: () -> Void
    let onTiming: (Int, Double, Double) -> Void
    let onSeek: (Double) -> Void
    /// Khi Skim bật, click tile chỉ chọn; preview/playhead không được giật về cue.
    let seeksOnClick: Bool

    func makeNSView(context: Context) -> SubtitleTimelineCueNSView { let view = SubtitleTimelineCueNSView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: SubtitleTimelineCueNSView, context: Context) {
        view.segments = segments; view.pixelsPerSecond = pixelsPerSecond
        view.selectedIDs = selectedIDs; view.primarySelectedID = primarySelectedID
        view.cueTrackCenterY = cueTrackCenterY
        view.isDarkTheme = isDarkTheme
        view.onSelect = onSelect; view.onMarqueeSelection = onMarqueeSelection
        view.onClearSelection = onClearSelection
        view.onTiming = onTiming; view.onSeek = onSeek
        view.seeksOnClick = seeksOnClick
        view.window?.invalidateCursorRects(for: view)
        view.needsDisplay = true
    }
}

final class SubtitleTimelineCueNSView: NSView {
    var segments: [SRTSegment] = []; var pixelsPerSecond = 80.0
    var selectedIDs: Set<Int> = []; var primarySelectedID: Int?
    var cueTrackCenterY: CGFloat?
    var isDarkTheme = false
    var onSelect: ((Int, TimelineCueSelectionIntent) -> Void)?; var onTiming: ((Int, Double, Double) -> Void)?
    var onMarqueeSelection: ((Set<Int>) -> Void)?; var onSeek: ((Double) -> Void)?
    var onClearSelection: (() -> Void)?
    var seeksOnClick = true
    private enum Drag { case none, move, trimIn, trimOut, scrub, marquee }
    private enum MarqueeMode { case replace, add, toggle }
    private var drag: Drag = .none; private var id: Int?; private var start = 0.0; private var end = 0.0
    private var liveStart = 0.0; private var liveEnd = 0.0; private var downPoint: NSPoint = .zero
    private var marqueeBand: NSRect?; private var marqueePreviewIDs: Set<Int>?
    private var selectionAtMouseDown: Set<Int> = []; private var marqueeMode: MarqueeMode = .replace
    private let edge: CGFloat = 9
    override var isFlipped: Bool { true }; override var acceptsFirstResponder: Bool { true }
    private func rect(_ segment: SRTSegment, start: Double? = nil, end: Double? = nil) -> NSRect {
        let s = start ?? segment.startSeconds, e = end ?? segment.endSeconds
        // Không nới cue ngắn thành 14 px: điều đó làm mép text/cue lệch waveform
        // khi zoom xa. Width phải luôn là time-scale thật; zoom vào để thao tác
        // các cue cực ngắn.
        let cueHeight = min(52, max(16, bounds.height - 44))
        let defaultY = max(22, bounds.height - 22 - cueHeight)
        let centeredY = cueTrackCenterY.map { $0 - cueHeight * 0.5 } ?? defaultY
        let cueY = min(max(8, centeredY), max(8, bounds.height - cueHeight - 8))
        return NSRect(x: CGFloat(s * pixelsPerSecond), y: cueY, width: max(1, CGFloat((e - s) * pixelsPerSecond)), height: cueHeight)
    }
    override func draw(_ dirtyRect: NSRect) {
        timelineBackground.setFill(); dirtyRect.fill()
        let displayedSelection = marqueePreviewIDs ?? selectedIDs
        for segment in segments {
            let active = id == segment.id && drag != .scrub
            let frame = rect(segment, start: active ? liveStart : nil, end: active ? liveEnd : nil)
            let selected = displayedSelection.contains(segment.id) || active
            let path = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            (selected ? selectedCueFill : idleCueFill).setFill(); path.fill()
            if selected {
                NSColor.white.withAlphaComponent(primarySelectedID == segment.id ? 0.92 : 0.62).setStroke()
                path.lineWidth = primarySelectedID == segment.id ? 1.35 : 0.8
                path.stroke()
            }
            // Hai đầu cue luôn có mũi tên trim khi đang chọn/kéo để phân biệt
            // rõ với vùng giữa (dời cả cue). Cả hai mép cũng dùng cursor ↔.
            if selected, frame.width >= 28 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.95)
                ]
                ("‹" as NSString).draw(at: NSPoint(x: frame.minX + 3, y: frame.midY - 8), withAttributes: attributes)
                ("›" as NSString).draw(at: NSPoint(x: frame.maxX - 10, y: frame.midY - 8), withAttributes: attributes)
            }
            if frame.width > 30 {
                let text = segment.text.replacingOccurrences(of: "\n", with: " ") as NSString
                let font = NSFont.systemFont(ofSize: 10, weight: selected ? .semibold : .medium)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.98 : 0.88)
                ]
                let lineHeight = ceil(font.ascender - font.descender + font.leading)
                let textRect = NSRect(
                    x: frame.minX + 8,
                    y: floor(frame.midY - lineHeight * 0.5),
                    width: max(1, frame.width - 16),
                    height: lineHeight + 2
                )
                NSGraphicsContext.current?.cgContext.saveGState()
                path.addClip()
                text.draw(in: textRect, withAttributes: attributes)
                NSGraphicsContext.current?.cgContext.restoreGState()
            }
        }
        if let marqueeBand {
            marqueeColor.withAlphaComponent(0.12).setFill(); marqueeBand.fill()
            marqueeColor.withAlphaComponent(0.82).setStroke()
            let path = NSBezierPath(rect: marqueeBand.insetBy(dx: 0.5, dy: 0.5)); path.lineWidth = 1; path.stroke()
        }
    }
    private var timelineBackground: NSColor {
        isDarkTheme
            ? NSColor(calibratedWhite: 0.118, alpha: 1)
            : NSColor(srgbRed: 0.82, green: 0.87, blue: 0.93, alpha: 1)
    }
    private var idleCueFill: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.14, green: 0.30, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.11, green: 0.30, blue: 0.62, alpha: 1)
    }
    private var selectedCueFill: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.10, green: 0.46, blue: 0.64, alpha: 1)
            : NSColor.systemBlue
    }
    private var marqueeColor: NSColor {
        isDarkTheme
            ? NSColor(srgbRed: 0.36, green: 0.58, blue: 0.76, alpha: 1)
            : NSColor.systemBlue
    }
    private func time(_ x: CGFloat) -> Double { max(0, Double(x) / pixelsPerSecond) }
    private func hit(_ point: NSPoint) -> (SRTSegment, Drag)? {
        for segment in segments.reversed() { let frame = rect(segment); if frame.contains(point) { return (segment, point.x < frame.minX + edge ? .trimIn : point.x > frame.maxX - edge ? .trimOut : .move) } }
        return nil
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); let point = convert(event.locationInWindow, from: nil); downPoint = point
        if let hit = hit(point) { drag = hit.1; id = hit.0.id; start = hit.0.startSeconds; end = hit.0.endSeconds; liveStart = start; liveEnd = end; onSelect?(hit.0.id, .from(event.modifierFlags)); switch drag { case .trimIn, .trimOut: NSCursor.resizeLeftRight.set(); case .move: NSCursor.closedHand.set(); default: break } } else { drag = .scrub }
        selectionAtMouseDown = selectedIDs
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        marqueeMode = flags.contains(.command) ? .toggle : flags.contains(.shift) ? .add : .replace
        marqueeBand = nil; marqueePreviewIDs = nil
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil); let delta = Double(point.x - downPoint.x) / pixelsPerSecond
        switch drag { case .move: let length = end - start; liveStart = max(0, start + delta); liveEnd = liveStart + length; needsDisplay = true
        case .trimIn: liveStart = min(liveEnd - 0.05, max(0, start + delta)); needsDisplay = true
        case .trimOut: liveEnd = max(liveStart + 0.05, end + delta); needsDisplay = true
        case .scrub:
            let deltaX = point.x - downPoint.x
            let deltaY = point.y - downPoint.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) >= 4 else { return }
            drag = .marquee; NSCursor.crosshair.set(); updateMarquee(to: point)
        case .marquee: updateMarquee(to: point)
        case .none: break }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { drag = .none; id = nil; marqueeBand = nil; marqueePreviewIDs = nil; NSCursor.arrow.set(); needsDisplay = true }
        if drag == .scrub {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !flags.contains(.command), !flags.contains(.shift) {
                onClearSelection?()
            }
            onSeek?(time(point.x))
            return
        }
        if drag == .marquee { onMarqueeSelection?(marqueePreviewIDs ?? []); return }
        if let id {
            onTiming?(id, liveStart, liveEnd)
            if seeksOnClick, abs(point.x - downPoint.x) < 2 { onSeek?(liveStart) }
        }
    }
    private func updateMarquee(to point: NSPoint) {
        let insetBounds = bounds.insetBy(dx: 1, dy: 1)
        let anchor = NSPoint(
            x: min(max(downPoint.x, insetBounds.minX), insetBounds.maxX),
            y: min(max(downPoint.y, insetBounds.minY), insetBounds.maxY)
        )
        let current = NSPoint(
            x: min(max(point.x, insetBounds.minX), insetBounds.maxX),
            y: min(max(point.y, insetBounds.minY), insetBounds.maxY)
        )
        let marqueeRect = NSRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: max(1, abs(current.x - anchor.x)),
            height: max(1, abs(current.y - anchor.y))
        )
        let hits = Set(segments.lazy.filter { self.rect($0).intersects(marqueeRect) }.map(\.id))
        marqueeBand = marqueeRect
        switch marqueeMode {
        case .replace: marqueePreviewIDs = hits
        case .add: marqueePreviewIDs = selectionAtMouseDown.union(hits)
        case .toggle: marqueePreviewIDs = selectionAtMouseDown.symmetricDifference(hits)
        }
        needsDisplay = true
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        for segment in segments {
            let frame = rect(segment)
            let left = NSRect(x: frame.minX, y: frame.minY, width: min(edge, frame.width * 0.5), height: frame.height)
            let right = NSRect(x: max(frame.minX, frame.maxX - edge), y: frame.minY, width: min(edge, frame.width * 0.5), height: frame.height)
            addCursorRect(left, cursor: .resizeLeftRight)
            addCursorRect(right, cursor: .resizeLeftRight)
            let middle = frame.insetBy(dx: min(edge, frame.width * 0.5), dy: 0)
            if middle.width > 0 { addCursorRect(middle, cursor: .openHand) }
        }
    }
}
