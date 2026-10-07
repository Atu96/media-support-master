import AVFoundation
import SwiftUI

/// Nền đen họa tiết khi chưa có video — gợi ý chọn media (font/màu chỉnh ở panel phải).
struct SubtitlePreviewStyleStage: View {
    let style: SubtitleBurnStyle

    var body: some View {
        GeometryReader { geo in
            let content = AVMakeRect(
                aspectRatio: CGSize(width: 16, height: 9),
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            let scale = max(0.35, content.height / 1080)

            ZStack {
                Color.black.opacity(0.92)

                ZStack {
                    SubtitlePreviewPatternBackground()

                    RadialGradient(
                        colors: [Color.clear, Color.black.opacity(0.45)],
                        center: .center,
                        startRadius: content.height * 0.15,
                        endRadius: content.height * 0.72
                    )

                    Image(systemName: "film.stack")
                        .font(.system(size: max(22, 28 * scale), weight: .light))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .frame(width: content.width, height: content.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .position(x: content.midX, y: content.midY)
            }
        }
        .id("style-\(style.fontName)-\(style.fontSize)-\(style.textColorHex)")
    }
}

typealias SubtitlePreviewSampleStage = SubtitlePreviewStyleStage

/// Nền đen + họa tiết grid / chéo / grain nhẹ (SwiftUI Canvas, không asset).
struct SubtitlePreviewPatternBackground: View {
    var body: some View {
        Canvas { context, size in
            // Base
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.04, green: 0.045, blue: 0.06))
            )

            // Gradient nhẹ góc
            let gradient = Gradient(colors: [
                Color(red: 0.09, green: 0.1, blue: 0.14).opacity(0.9),
                Color(red: 0.03, green: 0.03, blue: 0.05),
                Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.7),
            ])
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    gradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            let step: CGFloat = 28
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(grid, with: .color(Color.white.opacity(0.045)), lineWidth: 0.6)

            // Chéo mảnh
            var diag = Path()
            let dStep: CGFloat = 40
            var d: CGFloat = -size.height
            while d < size.width + size.height {
                diag.move(to: CGPoint(x: d, y: 0))
                diag.addLine(to: CGPoint(x: d + size.height, y: size.height))
                d += dStep
            }
            context.stroke(diag, with: .color(Color.white.opacity(0.03)), lineWidth: 0.5)

            // Chấm / grain thưa
            let cols = Int(size.width / 18)
            let rows = Int(size.height / 18)
            if cols > 0, rows > 0 {
                for row in 0...rows {
                    for col in 0...cols {
                        if (row + col) % 3 != 0 { continue }
                        let px = CGFloat(col) * 18 + 4
                        let py = CGFloat(row) * 18 + 4
                        let r: CGFloat = (row * 7 + col * 3) % 2 == 0 ? 1.1 : 0.7
                        let rect = CGRect(x: px, y: py, width: r, height: r)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color.white.opacity(0.055))
                        )
                    }
                }
            }

            // Khung film nhẹ hai mép
            let barH = max(6, size.height * 0.035)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: barH)),
                with: .color(Color.black.opacity(0.35))
            )
            context.fill(
                Path(CGRect(x: 0, y: size.height - barH, width: size.width, height: barH)),
                with: .color(Color.black.opacity(0.35))
            )
        }
        .allowsHitTesting(false)
    }
}

/// Alias cũ — tránh vỡ import nếu còn chỗ gọi.
typealias SubtitleStyleSamplePreview = SubtitlePreviewSampleStage
