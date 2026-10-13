import SwiftUI

/// Small ruler flag. The pole stays on the timestamp at either viewport edge;
/// only its triangular head shifts inward to remain visible.
struct TimelineMarkerFlag: View {
    var poleX: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let pole = min(size.width - 0.75, max(0.75, poleX))
            let head = min(size.width - 6, max(6, pole))
            var triangle = Path()
            triangle.move(to: CGPoint(x: head - 6, y: 3))
            triangle.addLine(to: CGPoint(x: head + 6, y: 3))
            triangle.addLine(to: CGPoint(x: pole, y: 14))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(AppTheme.accentOrange))
            var stem = Path()
            stem.move(to: CGPoint(x: pole, y: 14))
            stem.addLine(to: CGPoint(x: pole, y: 27))
            context.stroke(stem, with: .color(AppTheme.accentOrange),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 24, height: 32)
        .accessibilityHidden(true)
    }
}
