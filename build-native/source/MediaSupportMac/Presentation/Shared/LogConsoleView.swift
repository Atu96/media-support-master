import AppKit
import SwiftUI

struct LogConsoleView: View {
    @ObservedObject var runner: EngineRunner
    var title = "Nhật ký"
    /// Chiều cao vùng log (số dòng × ~16pt) — nil = panel lớn (120–200pt).
    var compactLines: Int? = nil
    /// Số dòng khi mở rộng ở chế độ neo đáy (đè lên nội dung phía trên).
    var expandedLines: Int? = nil
    var startsExpanded: Bool = true
    /// Neo sát đáy; mở rộng đè lên khối phía trên (tab Tạo sub).
    var pinsToBottom: Bool = false
    /// Nằm trong WorkspaceDockRow — header phẳng, không tile bo góc.
    var dockStyle: Bool = false
    var storageKey: String = "msm.logConsoleExpanded"
    /// Dòng trạng thái / xuất file — hiển thị trên log (tab Chỉnh sửa sub).
    var statusLines: [String] = []

    @State private var isExpanded = true
    @State private var didApplyStartState = false

    private var dockFooterHeight: CGFloat { AppTheme.dockBarHeight }

    private var activeLineCount: Int? {
        if pinsToBottom {
            return isExpanded ? (expandedLines ?? 10) : compactLines
        }
        return isExpanded ? compactLines : nil
    }

    private var bodyHeight: CGFloat? {
        guard let activeLineCount, activeLineCount > 0 else { return nil }
        return CGFloat(activeLineCount) * 16 + 8
    }

    var body: some View {
        Group {
            if pinsToBottom && dockStyle {
                bottomDockBody
            } else {
                standardBody
            }
        }
        .onAppear {
            guard !didApplyStartState else { return }
            if UserDefaults.standard.object(forKey: storageKey) != nil {
                isExpanded = UserDefaults.standard.bool(forKey: storageKey)
            } else {
                isExpanded = startsExpanded
            }
            didApplyStartState = true
        }
        .onChange(of: isExpanded) { _, expanded in
            UserDefaults.standard.set(expanded, forKey: storageKey)
        }
    }

    // MARK: - Dock đáy (Tạo sub / Chỉnh sửa)

    private var bottomDockBody: some View {
        ZStack(alignment: .bottomLeading) {
            if isExpanded {
                VStack(spacing: 0) {
                    if !statusLines.isEmpty {
                        statusBody
                        Rectangle()
                            .fill(AppTheme.divider.opacity(0.45))
                            .frame(height: 0.5)
                    }
                    compactLogScroll
                        .frame(height: bodyHeight, alignment: .topLeading)
                    Rectangle()
                        .fill(AppTheme.tileStroke.opacity(0.45))
                        .frame(height: 0.5)
                }
                .padding(.bottom, dockFooterHeight)
            }

            dockFooterBar
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .background {
            if isExpanded {
                AppTileSurface(radius: 0)
            }
        }
        .overlay(alignment: .top) {
            if isExpanded {
                Rectangle()
                    .fill(AppTheme.chromeRule)
                    .frame(height: 0.5)
            }
        }
        .zIndex(isExpanded ? 10 : 1)
    }

    private var dockFooterBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 12, height: 12)
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBlue)
                        .frame(width: 12, height: 12)
                    Text(L10n.string(title))
                        .font(AppFont.dockLabel)
                        .foregroundStyle(AppTheme.headlineText)
                        .fixedSize(horizontal: true, vertical: false)
                    if !runner.logLines.isEmpty {
                        Text("(\(runner.logLines.count))")
                            .font(AppFont.dockLabel)
                            .foregroundStyle(AppTheme.mutedText)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(height: dockFooterHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPlainButtonStyle())

            Spacer(minLength: 4)

            if runner.isRunning {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(AppTheme.accentOrange)
                    .frame(width: 14, height: 14)
            }

            if isExpanded {
                dockActionButton(
                    title: "Sao chép",
                    tint: AppTheme.accentBlue,
                    action: copyLog
                )

                dockActionButton(
                    title: "Xóa",
                    tint: AppTheme.accentOrange,
                    action: { runner.clearLog() }
                )
            }
        }
        .padding(.horizontal, AppTheme.dockLogHorizontalPadding)
        .frame(height: dockFooterHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dockActionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.string(title))
                .font(AppFont.dockLabel)
                .foregroundStyle(runner.logLines.isEmpty ? AppTheme.mutedText.opacity(0.45) : tint)
                .frame(height: dockFooterHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppPlainButtonStyle())
        .disabled(runner.logLines.isEmpty)
    }

    // MARK: - Panel thường (form / settings)

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            standardHeader
            if isExpanded {
                if !statusLines.isEmpty {
                    statusBody
                }
                logBody
            }
        }
        .background {
            if !dockStyle {
                AppTileSurface()
            }
        }

        .zIndex(pinsToBottom && isExpanded ? 10 : 0)
    }

    private var standardHeader: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 12)
                    Label(L10n.string(title), systemImage: "terminal")
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    if !runner.logLines.isEmpty {
                        Text("(\(runner.logLines.count))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText.opacity(0.8))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPlainButtonStyle())

            Spacer()

            if runner.isRunning {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(AppTheme.accentOrange)
            }

            if isExpanded {
                dockActionButton(title: "Sao chép", tint: AppTheme.accentBlue, action: copyLog)
                dockActionButton(title: "Xóa", tint: AppTheme.accentOrange, action: { runner.clearLog() })
            }
        }
        .padding(.horizontal, dockStyle ? 14 : (pinsToBottom ? 12 : 14))
        .padding(.vertical, dockStyle ? 7 : (pinsToBottom ? 8 : 12))
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(statusLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var logBody: some View {
        Group {
            if compactLines != nil {
                compactLogScroll
            } else {
                scrollLogBody
            }
        }
        .background {
            if dockStyle {
                AppTileSurface(radius: AppTheme.cardRadius)
            } else {
                AppFieldSurface(radius: AppTheme.cardRadius)
            }
        }
        .padding(.horizontal, dockStyle ? 10 : 14)
        .padding(.bottom, dockStyle ? 10 : 14)
    }

    private var compactLogScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if runner.logLines.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(AppFont.mono)
                                .foregroundStyle(logColor(for: line))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: runner.logLines.count) { _, _ in
                if let last = runner.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var scrollLogBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if runner.logLines.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .padding(14)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(runner.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(AppFont.mono)
                                .foregroundStyle(logColor(for: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(14)
                }
            }
            .frame(minHeight: 120, maxHeight: 200)
            .onChange(of: runner.logLines.count) { _, _ in
                if let last = runner.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func logColor(for line: String) -> Color {
        if line.contains("❌") || line.hasPrefix("✗") || line.contains("not found") {
            return AppTheme.accentRed
        }
        if line.contains("⚠️") {
            return AppTheme.accentOrange
        }
        if line.hasPrefix("✓") || line.hasPrefix("✅") {
            return AppTheme.accentGreen
        }
        return AppTheme.bodyText
    }

    private func copyLog() {
        let text = runner.logLines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
