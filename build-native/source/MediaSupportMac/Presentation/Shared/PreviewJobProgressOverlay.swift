import SwiftUI

/// Vòng viền sáng/tối mỏng xoay + % giữa khung preview (job Whisper / align).
struct PreviewJobProgressOverlay: View {
    let percent: Int
    @State private var rotating = false

    private var clamped: Int { min(100, max(0, percent)) }

    var body: some View {
        ZStack {
            // Nền mờ nhẹ cho chữ đọc được
            Circle()
                .fill(.black.opacity(0.28))
                .frame(width: 88, height: 88)
                .blur(radius: 0.5)

            // Đĩa glass
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 76, height: 76)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            // Vành xoay mỏng (sáng → tối)
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.9),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .frame(width: 82, height: 82)
                .rotationEffect(.degrees(rotating ? 360 : 0))
                .animation(
                    .linear(duration: 1.15).repeatForever(autoreverses: false),
                    value: rotating
                )

            // % trong tâm
            Text("\(clamped)%")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: clamped)
        }
        .allowsHitTesting(false)
        .onAppear { rotating = true }
    }
}
