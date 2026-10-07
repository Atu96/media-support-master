import AppKit
import AVFoundation
import SwiftUI

/// The same shaped glyphs and animation tree as native export, scrubbed at cue time.
struct SubtitlePreviewOverlayView: View {
    @State private var demoProgress: Double?
    @State private var demoTask: Task<Void, Never>?
    @State private var demoRequest = 0
    let text: String
    let opacity: Double
    let style: SubtitleBurnStyle
    let cueProgress: Double
    let cueDuration: Double
    let cueSeed: Int
    var decorationDensity: Int = 8
    var videoAspectRatio: CGFloat = 16 / 9
    var referencePixelHeight: CGFloat = 1080

    var body: some View {
        NativeSubtitleLayerPreview(
            text: text, style: style, progress: demoProgress ?? cueProgress,
            duration: cueDuration, seed: cueSeed, density: decorationDensity,
            aspectRatio: videoAspectRatio
        )
        .opacity(opacity)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .msmSubtitleStylePresetPreviewRequested)) { _ in
            demoRequest += 1
        }
        // Observe after SwiftUI applies the style and request in one update;
        // the synchronous notification itself may still see the previous preset.
        .onChange(of: demoRequest) { _, _ in startDemo() }
        .onChange(of: cueProgress) { _, _ in cancelDemo() }
        .onChange(of: text) { _, _ in cancelDemo() }
        .onChange(of: cueSeed) { _, _ in cancelDemo() }
        .onDisappear { cancelDemo() }
    }

    private func cancelDemo() {
        demoTask?.cancel()
        demoTask = nil
        demoProgress = nil
    }

    private func startDemo() {
        cancelDemo()
        guard style.textTransition != .none || style.visualEffect != .none else { return }
        // Keep demo local; moving time/cue or leaving this view cancels it.
        demoTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let sweep = style.goldenSweepTiming(forCueDuration: cueDuration)
            let end = max(style.transitionEntranceDuration(forCueDuration: cueDuration),
                          style.visualEffect == .goldenSweep ? sweep.delay + sweep.duration : 0.6)
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let fraction = min(1, seconds / 1.2)
                demoProgress = min(0.999, fraction * end / max(cueDuration, 0.001))
                if fraction >= 1 { break }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            guard !Task.isCancelled else { return }
            demoProgress = nil
        }
    }

    /// Text hiển thị: live draft (đang gõ) → dòng focus → dòng theo time. **Không** re-wrap lại.
    static func resolveDisplayText(
        segments: [SRTSegment],
        currentTime: Double,
        focusSegmentID: Int?,
        isPlaying: Bool,
        liveEditDraft: (id: Int, text: String)?
    ) -> (text: String, segment: SRTSegment)? {
        if let live = liveEditDraft,
           let seg = segments.first(where: { $0.id == live.id }) {
            let t = live.text.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : (t, seg)
        }

        let seg: SRTSegment?
        if !isPlaying, let focusSegmentID,
           let focused = segments.first(where: { $0.id == focusSegmentID }) {
            seg = focused
        } else {
            seg = segments.segment(at: currentTime)
        }
        guard let seg else { return nil }
        let t = seg.text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return (seg.text, seg)
    }

    static func make(
        segments: [SRTSegment],
        currentTime: Double,
        style: SubtitleBurnStyle,
        focusSegmentID: Int? = nil,
        isPlaying: Bool = false,
        liveEditDraft: (id: Int, text: String)? = nil,
        videoAspectRatio: CGFloat,
        referencePixelHeight: CGFloat
    ) -> SubtitlePreviewOverlayView? {
        guard let resolved = resolveDisplayText(
            segments: segments,
            currentTime: currentTime,
            focusSegmentID: focusSegmentID,
            isPlaying: isPlaying,
            liveEditDraft: liveEditDraft
        ) else { return nil }

        return SubtitlePreviewOverlayView(
            text: resolved.text,
            // Cue app-only không dùng fade dùng chung: phần đã reveal luôn rõ 100%.
            opacity: 1,
            style: style,
            cueProgress: max(0, min(1, (currentTime - resolved.segment.startSeconds) / max(resolved.segment.durationSeconds, 0.001))),
            cueDuration: resolved.segment.durationSeconds,
            cueSeed: resolved.segment.id,
            decorationDensity: max(2, min(style.effectDensity, 720 / max(1, segments.count))),
            videoAspectRatio: videoAspectRatio,
            referencePixelHeight: referencePixelHeight
        )
    }


}

extension Notification.Name {
    static let msmSubtitleStylePresetPreviewRequested = Notification.Name("msm.subtitleStylePresetPreviewRequested")
}

private struct NativeSubtitleLayerPreview: NSViewRepresentable {
    let text: String
    let style: SubtitleBurnStyle
    let progress: Double
    let duration: Double
    let seed: Int
    let density: Int
    let aspectRatio: CGFloat

    func makeNSView(context: Context) -> SubtitleLayerHost { SubtitleLayerHost() }
    func updateNSView(_ view: SubtitleLayerHost, context: Context) {
        view.update(text: text, style: style, progress: progress, duration: duration,
                    seed: seed, density: density, aspectRatio: aspectRatio)
    }
}

private final class SubtitleLayerHost: NSView {
    private var cachedText = ""
    private var cachedStyle: SubtitleBurnStyle?
    private var cachedDuration: Double = -1
    private var cachedSeed = -1
    private var cachedDensity = -1
    private var aspect: CGFloat = 16 / 9
    private var currentProgress = 0.0
    private var renderedSize = CGSize.zero
    private var stage: CALayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(text: String, style: SubtitleBurnStyle, progress: Double,
                duration: Double, seed: Int, density: Int, aspectRatio: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let ratio = max(0.01, aspectRatio)
        currentProgress = progress
        if text != cachedText || style != cachedStyle || duration != cachedDuration
            || seed != cachedSeed || density != cachedDensity || ratio != aspect {
            cachedText = text; cachedStyle = style; cachedDuration = duration
            cachedSeed = seed; cachedDensity = density; aspect = ratio
            rebuildStage(force: true)
        }
        updateStageTime()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildStage(force: false)
        updateStageTime()
        CATransaction.commit()
    }

    /// Render directly at the visible video rectangle. Scaling a 1080p layer
    /// tree to a fractional Retina size makes thin strokes and outlines soft.
    /// Export still supplies its real render size to the same renderer.
    private func rebuildStage(force: Bool) {
        let rect = AVMakeRect(aspectRatio: CGSize(width: aspect, height: 1), insideRect: bounds)
        guard rect.width >= 2, rect.height >= 2 else { return }
        let target = CGSize(width: rect.width.rounded(.toNearestOrAwayFromZero),
                            height: rect.height.rounded(.toNearestOrAwayFromZero))
        guard force || abs(target.width - renderedSize.width) >= 1
                || abs(target.height - renderedSize.height) >= 1 else {
            stage?.position = rect.origin
            return
        }
        stage?.removeFromSuperlayer()
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: target)
        root.position = rect.origin
        root.anchorPoint = .zero
        root.speed = 0
        root.masksToBounds = false
        let segment = SRTSegment(id: cachedSeed, index: cachedSeed, timing: "",
                                 startSeconds: 0, endSeconds: max(0.001, cachedDuration), text: cachedText)
        if let cachedStyle {
            root.addSublayer(SubtitleCueLayerRenderer.makeCueLayer(
                segment: segment, style: cachedStyle, renderSize: target,
                decorationDensity: cachedDensity
            ))
        }
        layer?.addSublayer(root)
        stage = root
        renderedSize = target
    }

    private func updateStageTime() {
        stage?.timeOffset = max(0.00001, min(0.999999, currentProgress) * max(0.001, cachedDuration))
    }
}
