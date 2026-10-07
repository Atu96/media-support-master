import SwiftUI

/// Play / scrub bên dưới khung video — núm glass; job mode: thanh chạy theo tiến trình.
struct PreviewTransportBar: View {
    @ObservedObject var preview: AVPreviewService
    /// Khi job chạy: thanh kéo bám % (không tua tay).
    var jobProgressPercent: Int?
    var scrubEnabled: Bool = true

    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private var isJobMode: Bool {
        jobProgressPercent != nil
    }

    private var canScrub: Bool {
        scrubEnabled && !isJobMode && preview.isLoaded
    }

    private var displayTime: Double {
        if isScrubbing { return scrubTime }
        if isJobMode, let pct = jobProgressPercent, preview.duration > 0 {
            return preview.duration * Double(pct) / 100.0
        }
        return preview.currentTime
    }

    private var displayDuration: Double {
        max(preview.duration, 0.01)
    }

    private var sliderValue: Double {
        if isJobMode, let pct = jobProgressPercent, preview.duration > 0 {
            return preview.duration * Double(pct) / 100.0
        }
        if isJobMode, let pct = jobProgressPercent {
            return Double(pct) / 100.0
        }
        if isScrubbing { return scrubTime }
        return preview.currentTime
    }

    private var sliderRange: ClosedRange<Double> {
        if isJobMode, preview.duration <= 0 {
            return 0...1
        }
        return 0...displayDuration
    }

    var body: some View {
        HStack(spacing: 12) {
            if !isJobMode {
                AppPillButton(
                    title: preview.isPlaying ? "Tạm dừng" : "Phát",
                    icon: preview.isPlaying ? "pause.fill" : "play.fill",
                    tint: AppTheme.accentBlue,
                    filled: true,
                    disabled: !preview.isLoaded
                ) {
                    preview.togglePlayPause()
                }
            }

            glassScrubber
                .frame(maxWidth: .infinity)
                .frame(height: 28)

            if !isJobMode {
                if preview.duration > 0 {
                    Text("\(timeLabel(displayTime)) / \(timeLabel(displayDuration))")
                        .font(AppFont.mono)
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 96, alignment: .trailing)
                } else {
                    Text(timeLabel(displayTime))
                        .font(AppFont.mono)
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 96, alignment: .trailing)
                }
            }
        }
        .opacity(preview.isLoaded || isJobMode ? 1 : 0.45)
    }

    /// Thanh + núm tròn glass (vừa phải).
    private var glassScrubber: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let range = sliderRange
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let t = (sliderValue - range.lowerBound) / span
            let x = max(0, min(1, t)) * w
            let trackH: CGFloat = 4
            let thumb: CGFloat = 16

            ZStack(alignment: .leading) {
                // Track nền
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackH)
                    .frame(maxVerticalAlignment: .center)

                // Phần đã chạy
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isJobMode
                                ? [AppTheme.accentOrange.opacity(0.95), AppTheme.accentOrange.opacity(0.65)]
                                : [AppTheme.accentBlue, AppTheme.accentBlue.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumb / 2, x), height: trackH)
                    .animation(isJobMode ? .linear(duration: 0.2) : nil, value: sliderValue)

                // Núm glass
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: thumb, height: thumb)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.85),
                                        Color.white.opacity(0.2),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    .offset(x: max(0, min(w - thumb, x - thumb / 2)))
                    .animation(isJobMode ? .linear(duration: 0.2) : nil, value: sliderValue)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canScrub else { return }
                        isScrubbing = true
                        let ratio = max(0, min(1, value.location.x / w))
                        let newVal = range.lowerBound + ratio * span
                        scrubTime = newVal
                        preview.seek(seconds: newVal, playAfter: false, precise: true)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                    }
            )
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private extension View {
    func frame(maxVerticalAlignment alignment: Alignment) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
