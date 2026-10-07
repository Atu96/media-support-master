import SwiftUI

struct EngineStatusBadge: View {
    let status: EngineStatus

    var body: some View {
        if !status.isReady {
            HStack(spacing: 8) {
                AppStatusDot(isActive: false)
                Text("Thiếu dependency")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.accentOrange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.tileFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.tileStroke, lineWidth: 0.75)
                    )
            )
        }
    }
}