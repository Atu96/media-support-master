import SwiftUI

enum EngineResourceBarPlacement {
    /// Đáy cửa sổ — full width, glass.
    case window
    /// Ô phải dock — nền do WorkspaceDockRow cung cấp.
    case dock
}

/// Thanh RAM/CPU/job.
struct EngineResourceBar: View {
    var placement: EngineResourceBarPlacement = .window

    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var monitor = SystemResourceMonitor.shared

    private var runner: EngineRunner {
        coordinator.engine.runner
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: runner.isRunning ? "gauge.with.dots.needle.67percent" : "gauge")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(runner.isRunning ? AppTheme.accentOrange : AppTheme.accentBlue)
                .frame(width: 14, height: 14)
            Text(monitor.snapshot.summaryLine)
                .font(AppFont.dockMono)
                .foregroundStyle(AppTheme.headlineText)
                .lineLimit(1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if runner.isRunning, let job = runner.currentJobTitle {
                Text(job)
                    .font(AppFont.dockLabel)
                    .foregroundStyle(AppTheme.accentOrange)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            AppSupportButton().fixedSize()
        }
        .padding(.horizontal, placement == .dock ? 0 : 14)
        .padding(.leading, placement == .dock ? AppTheme.dockResourceLeadingPadding : 0)
        .padding(.trailing, placement == .dock ? AppTheme.dockResourceTrailingPadding : 0)
        .padding(.vertical, placement == .dock ? 0 : 6)
        .frame(height: placement == .dock ? AppTheme.dockBarHeight : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            monitor.startPolling(every: 2)
        }
        .onChange(of: runner.isRunning) { _, running in
            if running {
                monitor.startPolling(every: 1.5)
            } else {
                monitor.setEnginePID(nil)
                monitor.refresh()
            }
        }
    }
}
