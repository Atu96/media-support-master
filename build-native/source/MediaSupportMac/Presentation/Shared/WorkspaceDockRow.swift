import SwiftUI

private var workspaceColumnDivider: some View {
    Rectangle()
        .fill(AppTheme.divider.opacity(0.55))
        .frame(height: 0.5)
}

/// Thanh đáy phẳng — nhật ký trái, tài nguyên phải, một nền liền.
struct WorkspaceDockRow<Left: View, Right: View>: View {
    let leftWidth: CGFloat
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            left()
                .frame(width: leftWidth, height: AppTheme.dockBarHeight, alignment: .leading)
                .clipped()
            Rectangle()
                .fill(AppTheme.chromeRule)
                .frame(width: 0.5)
                .frame(maxHeight: .infinity)
            right()
                .frame(maxWidth: .infinity, maxHeight: AppTheme.dockBarHeight, alignment: .leading)
                .frame(height: AppTheme.dockBarHeight)
                .clipped()
        }
        .frame(height: AppTheme.dockBarHeight)
        .frame(maxWidth: .infinity)
    }
}

/// Cột công cụ trái — một khối tile (tab khác nếu cần).
struct WorkspaceLeftToolColumn<Content: View, Footer: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxHeight: .infinity, alignment: .top)
            workspaceColumnDivider
            footer()
                .frame(height: AppTheme.dockBarHeight)
        }
        .frame(width: width, height: height)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

/// Dock đáy: nhật ký (trái, mở rộng đè lên) ‖ RAM/CPU (phải).
struct WorkspaceSplitDock<Log: View>: View {
    let logWidth: CGFloat
    @ViewBuilder var log: () -> Log

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WorkspaceDockRow(leftWidth: logWidth) {
                Color.clear
            } right: {
                EngineResourceBar(placement: .dock)
            }

            log()
                .frame(width: logWidth, alignment: .bottomLeading)
                .fixedSize(horizontal: false, vertical: true)
                .zIndex(5)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
    }
}