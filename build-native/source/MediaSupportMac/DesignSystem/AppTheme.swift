import AppKit
import SwiftUI

// MARK: - Adaptive glass editor palette
// Một bộ semantic token duy nhất cho Sáng/Tối. Không đảo màu cơ học: nền, chữ,
// viền và trạng thái điều khiển đều có giá trị riêng để giữ tương phản ổn định.

enum AppTheme {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let accentBlue = adaptive(
        light: rgb(0.04, 0.42, 0.96),
        dark: rgb(0.25, 0.50, 0.80)
    )
    static let accentCyan = adaptive(
        light: rgb(0.05, 0.64, 0.88),
        dark: rgb(0.28, 0.62, 0.74)
    )
    static let accentGreen = adaptive(light: rgb(0.08, 0.65, 0.38), dark: rgb(0.25, 0.82, 0.53))
    static let accentOrange = adaptive(light: rgb(0.88, 0.46, 0.06), dark: rgb(1.00, 0.65, 0.22))
    static let accentRed = adaptive(light: rgb(0.88, 0.18, 0.22), dark: rgb(1.00, 0.39, 0.42))

    // Dark dùng hierarchy kiểu editor chuyên nghiệp: header than đậm, panel
    // graphite trung bình. Không dùng gần-đen cho toàn workspace vì empty state
    // sẽ buộc người dùng tăng độ sáng màn hình.
    static let oceanSky = adaptive(light: rgb(0.955, 0.972, 0.992), dark: rgb(0.135, 0.138, 0.143))
    static let oceanMid = adaptive(light: rgb(0.925, 0.950, 0.980), dark: rgb(0.150, 0.153, 0.158))
    static let oceanDeep = adaptive(light: rgb(0.875, 0.915, 0.960), dark: rgb(0.168, 0.171, 0.177))
    static let oceanAbyss = adaptive(light: rgb(0.825, 0.875, 0.935), dark: rgb(0.105, 0.108, 0.113))
    static let oceanShimmer = adaptive(light: .white, dark: rgb(0.38, 0.40, 0.44))

    static let shellTop = oceanSky
    static let shellMid = oceanMid
    static let shellBottom = oceanDeep
    static let shellGlow = oceanShimmer
    static let sidebarTop = adaptive(light: rgb(0.78, 0.89, 0.98), dark: rgb(0.180, 0.184, 0.190))
    static let sidebarBottom = adaptive(light: rgb(0.66, 0.80, 0.95), dark: rgb(0.150, 0.153, 0.158))
    static let sidebarSelection = adaptive(light: rgb(1, 1, 1, alpha: 0.68), dark: rgb(0.20, 0.22, 0.25, alpha: 0.94))

    static let tileFill = adaptive(light: rgb(0.985, 0.992, 1.0, alpha: 0.78), dark: rgb(0.175, 0.178, 0.184, alpha: 0.99))
    // Dark editor: rãnh graphite mảnh như FCP, phân cấp bằng surface thay vì
    // vẽ khung sáng quanh mọi block. Strong chỉ dùng cho control/focus thật.
    static let tileStroke = adaptive(light: rgb(0.34, 0.45, 0.58, alpha: 0.30), dark: rgb(0.58, 0.61, 0.66, alpha: 0.22))
    static let tileStrokeStrong = adaptive(light: rgb(0.25, 0.40, 0.58, alpha: 0.48), dark: rgb(0.72, 0.75, 0.80, alpha: 0.42))
    static let glassTint = adaptive(light: rgb(1, 1, 1, alpha: 0.22), dark: rgb(0.18, 0.19, 0.21, alpha: 0.58))
    static let glassSpecular = adaptive(light: rgb(1, 1, 1, alpha: 0.62), dark: rgb(0.70, 0.74, 0.81, alpha: 0.08))
    static let divider = adaptive(light: rgb(0.30, 0.40, 0.52, alpha: 0.25), dark: rgb(0.56, 0.59, 0.64, alpha: 0.30))
    static let controlFill = adaptive(light: rgb(1, 1, 1, alpha: 0.52), dark: rgb(0.215, 0.220, 0.230, alpha: 0.92))
    static let controlHover = adaptive(light: rgb(0.09, 0.45, 0.96, alpha: 0.10), dark: rgb(0.36, 0.67, 0.84, alpha: 0.18))
    static let controlPressed = adaptive(light: rgb(0.07, 0.39, 0.86, alpha: 0.16), dark: rgb(0.34, 0.65, 0.86, alpha: 0.25))
    static let focusRing = accentBlue
    static let specularLine = adaptive(light: rgb(1, 1, 1, alpha: 0.82), dark: rgb(0.82, 0.86, 0.92, alpha: 0.22))

    static let titleText = adaptive(light: rgb(0.025, 0.065, 0.13), dark: rgb(0.94, 0.95, 0.97))
    static let headlineText = adaptive(light: rgb(0.045, 0.09, 0.17), dark: rgb(0.89, 0.91, 0.94))
    static let bodyText = adaptive(light: rgb(0.10, 0.15, 0.23), dark: rgb(0.80, 0.83, 0.88))
    static let mutedText = adaptive(light: rgb(0.29, 0.38, 0.50), dark: rgb(0.66, 0.70, 0.76))
    static let shellText = titleText
    static let shellTextMuted = mutedText
    static let dockText = headlineText
    static let dockTextMuted = mutedText
    static let dockTextAccent = accentBlue
    static let captionText = mutedText

    static let inputFill = adaptive(light: rgb(0.985, 0.992, 1, alpha: 0.86), dark: rgb(0.205, 0.210, 0.220, alpha: 0.99))
    static let insetFill = adaptive(light: rgb(0.80, 0.87, 0.94, alpha: 0.38), dark: rgb(0.125, 0.128, 0.135, alpha: 0.96))

    // Editor dark dùng màu chọn trầm, giảm diện tích xanh rực quanh preview.
    // Action vẫn nhận diện được nhưng không tranh tiêu điểm với hình ảnh/video.
    static let editorAccent = adaptive(light: rgb(0.04, 0.42, 0.96), dark: rgb(0.30, 0.68, 0.86))
    static let editorActiveFill = adaptive(light: rgb(0.04, 0.42, 0.96), dark: rgb(0.10, 0.34, 0.43))
    static let editorSelectionFill = adaptive(light: rgb(0.04, 0.42, 0.96), dark: rgb(0.10, 0.42, 0.58))

    // Timeline là một editor inset, nhưng vẫn thuộc đúng theme hiện hành.
    // Light dùng slate-blue dịu thay cho mảng đen tuyệt đối; dark giữ navy sâu.
    static let timelineCanvasFill = adaptive(light: rgb(0.82, 0.87, 0.93), dark: rgb(0.130, 0.133, 0.138))
    static let timelineWaveformFill = adaptive(light: rgb(0.72, 0.80, 0.89), dark: rgb(0.055, 0.100, 0.170))
    static let timelineRulerFill = adaptive(light: rgb(0.88, 0.92, 0.96), dark: rgb(0.140, 0.145, 0.152))
    static let timelineLabelText = adaptive(light: rgb(0.24, 0.34, 0.46), dark: rgb(0.68, 0.73, 0.80))
    static let timelineClickMarker = adaptive(light: rgb(0.86, 0.56, 0.03), dark: rgb(1.0, 0.78, 0.18))

    static let contentMaxWidth: CGFloat = 720
    static let cardRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 9
    static let fieldRadius: CGFloat = 9
    static let editorPanelRadius: CGFloat = 0
    static let editorControlRadius: CGFloat = 6
    static let editorFieldRadius: CGFloat = 8
    static let overlayRadius: CGFloat = 10
    static let hairlineWidth: CGFloat = 0.5
    static let controlStrokeWidth: CGFloat = 0.5
    static let selectedStrokeWidth: CGFloat = 1
    static let compactControlHeight: CGFloat = 28
    static let compactIconSize: CGFloat = 12
    static let controlGap: CGFloat = 6
    static let workspaceColumnGap: CGFloat = 6
    static let workspaceRowGap: CGFloat = 6
    /// Khung hàng điều khiển preview (40) — căn ngang với hàng Chép lời / Tạo sub; nút Phát giữ kích thước gốc.
    static let workspaceTransportRowHeight: CGFloat = 40
    static let workspaceCellPadding: CGFloat = 10
    static let workspaceCellStackGap: CGFloat = 8
    static let chromeTopHairline: CGFloat = 0.5
    /// Header editor gọn: chừa vừa đủ dưới traffic light, không tạo khoảng trời trống.
    static let chromeTitlebarInset: CGFloat = 6
    static let moduleTabBarHeight: CGFloat = 34
    static var workspaceHeaderHeight: CGFloat { chromeTitlebarInset + moduleTabBarHeight }
    /// Viền phân cách — cùng tông, mỏng (trên / trái / header / cửa sổ).
    static let chromeRule = divider
    static let chromeStripWidth: CGFloat = 44
    static let dockBarHeight: CGFloat = 32
    static let settingsSheetSize = CGSize(width: 920, height: 680)
    static let dockLogHorizontalPadding: CGFloat = 12
    static let dockResourceLeadingPadding: CGFloat = 20
    static let dockResourceTrailingPadding: CGFloat = 16
    static var dockFootprint: CGFloat { dockBarHeight }
    static let pillRadius: CGFloat = 20
    static let rowHeight: CGFloat = 38

    static func statusColor(isActive: Bool) -> Color {
        isActive ? accentGreen : accentOrange
    }
}

enum AppFont {
    static let pageTitle = Font.system(size: 24, weight: .bold)
    static let pageSubtitle = Font.system(size: 13, weight: .regular)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .medium)
    static let label = Font.system(size: 12, weight: .medium)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let dockLabel = Font.system(size: 11, weight: .semibold)
    static let dockMono = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let editorMicro = Font.system(size: 9, weight: .medium)
    static let editorLabel = Font.system(size: 10, weight: .semibold)
    static let editorBody = Font.system(size: 11, weight: .regular)
    static let editorBodyStrong = Font.system(size: 11, weight: .semibold)
    static let editorTimecode = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let previewTimecode = Font.system(size: 18, weight: .regular, design: .monospaced)
}

// MARK: - Backgrounds

struct AppShellGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                // CapCut/FCP dùng nhiều cấp graphite thay vì phủ một mảng đen.
                // Gradient rất nhẹ, không blur/material nên giữ chi phí redraw thấp.
                LinearGradient(
                    colors: [AppTheme.oceanDeep, AppTheme.oceanSky],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            AppTheme.oceanSky,
                            AppTheme.oceanMid,
                            AppTheme.oceanDeep,
                            AppTheme.oceanAbyss
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [AppTheme.oceanShimmer.opacity(0.48), Color.clear],
                        center: UnitPoint(x: 0.12, y: 0.06),
                        startRadius: 20,
                        endRadius: 520
                    )

                    RadialGradient(
                        colors: [AppTheme.accentCyan.opacity(0.10), Color.clear],
                        center: UnitPoint(x: 0.88, y: 0.08),
                        startRadius: 30,
                        endRadius: 560
                    )

                    RadialGradient(
                        colors: [AppTheme.accentBlue.opacity(0.06), Color.clear],
                        center: UnitPoint(x: 0.92, y: 0.90),
                        startRadius: 30,
                        endRadius: 560
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct AppSidebarGradient: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.sidebarTop, AppTheme.sidebarBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Rule ngang dưới hàng nav — phân tách workspace.
struct AppChromeHeaderRule: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: AppTheme.workspaceHeaderHeight)
            Rectangle()
                .fill(AppTheme.chromeRule)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}

/// Toolbar editor mảnh: tên dự án · tab · trạng thái/model, căn sát dưới traffic light.
struct AppModuleHeaderBand<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, max(2, AppTheme.chromeTitlebarInset - 4))
            .frame(height: AppTheme.workspaceHeaderHeight, alignment: .top)
    }
}

struct AppWindowBackground: View {
    var body: some View {
        AppShellGradient()
    }
}

struct AppTileSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = AppTheme.cardRadius

    var body: some View {
        let isDark = colorScheme == .dark
        let resolvedRadius = isDark ? min(radius, 6) : radius
        return RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
            .fill(AppTheme.tileFill)
            .overlay {
                if !isDark && !reduceTransparency {
                    RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.36))
                }
            }
            .overlay {
                if !isDark {
                    RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.glassSpecular,
                                    Color.clear,
                                    AppTheme.accentBlue.opacity(0.045)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                    .strokeBorder(
                        isDark ? AppTheme.tileStroke : Color.clear,
                        lineWidth: isDark ? 0.5 : 0
                    )
            )
            .shadow(color: isDark ? .clear : AppTheme.titleText.opacity(0.07), radius: isDark ? 0 : 7, y: isDark ? 0 : 3)
    }
}

struct AppFieldSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = AppTheme.fieldRadius

    var body: some View {
        let isDark = colorScheme == .dark
        let resolvedRadius = isDark ? min(radius, AppTheme.editorControlRadius) : radius
        return RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
            .fill(AppTheme.inputFill)
            .overlay {
                if !isDark && !reduceTransparency {
                    RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                        .fill(.thinMaterial.opacity(0.24))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                    .strokeBorder(AppTheme.tileStroke, lineWidth: isDark ? AppTheme.hairlineWidth : 0.75)
            )
    }
}

// MARK: - Section chrome (giống "Battery", "Connectivity")

struct AppSectionHeader: View {
    let title: String

    var body: some View {
        Text(L10n.string(title).uppercased())
            .font(AppFont.sectionHeader)
            .foregroundStyle(AppTheme.mutedText)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(title))
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppTheme.headlineText)
                    if let subtitle {
                        Text(L10n.string(subtitle))
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTileSurface())
    }
}

struct AppWorkflowStep<Content: View>: View {
    let number: Int
    let title: String
    let hint: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentBlue.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text("\(number)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.accentBlue)
                }
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string(title))
                            .font(AppFont.sectionTitle)
                            .foregroundStyle(AppTheme.headlineText)
                        Text(L10n.string(hint))
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct AppFileField: View {
    let label: String
    let placeholder: String
    let filename: String?
    let chooseTitle: String
    let onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.accentBlue.opacity(0.85))
                Text(filename ?? L10n.string(placeholder))
                    .font(AppFont.body)
                    .foregroundStyle(filename == nil ? AppTheme.mutedText : AppTheme.headlineText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                AppPillButton(title: chooseTitle, icon: "folder", tint: AppTheme.accentBlue, action: onChoose)
            }
            .padding(.horizontal, 12)
            .frame(height: AppTheme.rowHeight)
            .background(AppFieldSurface())
        }
    }
}

struct AppPillButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = AppTheme.accentBlue
    var filled: Bool = false
    var disabled: Bool = false
    var highlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(L10n.string(title))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(filled || highlighted ? Color.white : tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(buttonFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(highlighted ? Color.clear : (filled ? tint.opacity(0.72) : AppTheme.tileStrokeStrong), lineWidth: 0.8)
                    )
            )
            .overlay {
                if highlighted {
                    Capsule(style: .continuous)
                        .stroke(AppTheme.specularLine, lineWidth: 1.5)
                        .shadow(color: AppTheme.accentGreen.opacity(0.55), radius: 10, y: 0)
                }
            }
            .scaleEffect(highlighted ? 1.04 : 1)
            .animation(.easeInOut(duration: 0.28), value: highlighted)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(AppPressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var buttonFill: Color {
        if highlighted { return AppTheme.accentGreen }
        if filled { return tint }
        return AppTheme.tileFill
    }
}

struct AppActionRow: View {
    var primaryTitle: String
    var primaryIcon: String? = nil
    var primaryDisabled: Bool = false
    var onPrimary: () -> Void
    var secondary: [AppSecondaryAction] = []

    var body: some View {
        HStack(spacing: 10) {
            ForEach(secondary.indices, id: \.self) { index in
                let action = secondary[index]
                AppPillButton(
                    title: action.title,
                    icon: action.icon,
                    tint: action.tint ?? AppTheme.accentBlue,
                    disabled: action.disabled,
                    action: action.handler
                )
            }
            Spacer(minLength: 0)
            AppPillButton(
                title: primaryTitle,
                icon: primaryIcon,
                tint: AppTheme.accentBlue,
                filled: true,
                disabled: primaryDisabled,
                action: onPrimary
            )
        }
    }
}

struct AppSecondaryAction {
    let title: String
    var icon: String? = nil
    var tint: Color? = nil
    var disabled: Bool = false
    let handler: () -> Void
}

struct FeaturePageLayout<Content: View>: View {
    let title: String
    let subtitle: String
    var wide = false
    var compact = false
    var showTitle = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 18) {
            if compact && showTitle {
                Text(L10n.string(title))
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.titleText)
            } else if !compact {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(title))
                        .font(AppFont.pageTitle)
                        .foregroundStyle(AppTheme.titleText)
                    Text(L10n.string(subtitle))
                        .font(AppFont.pageSubtitle)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            content()
        }
        .frame(maxWidth: wide ? .infinity : AppTheme.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .topLeading)
    }
}

struct AppStatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(AppTheme.statusColor(isActive: isActive))
            .frame(width: 8, height: 8)
    }
}

struct AppMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(AppTheme.accentBlue)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

extension View {
    /// Mở rộng vùng nhận chuột — padding âm không đổi layout / giao diện.
    func appButtonHitTarget(padding horizontal: CGFloat = 8, vertical: CGFloat = 6) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
            .contentShape(Rectangle())
    }
}

/// Thay `.plain` — chỉ mở rộng hit area, không đổi nét vẽ.
struct AppPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appButtonHitTarget()
    }
}

struct AppPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appButtonHitTarget(padding: 6, vertical: 5)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

enum AppColorTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Theo hệ thống"
        case .light: "Sáng"
        case .dark: "Tối"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Đồng bộ SwiftUI, AppKit và các cửa sổ preview theo lựa chọn của người dùng.
@MainActor
enum AppAppearance {
    static let storageKey = "msm.appearance.colorTheme"

    static var selectedTheme: AppColorTheme {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppColorTheme.system.rawValue
        return AppColorTheme(rawValue: raw) ?? .system
    }

    static func apply(to window: NSWindow?) {
        switch selectedTheme {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func refreshAllWindows() {
        NSApp.windows.forEach(apply(to:))
    }
}

/// Thanh đáy — mirror glass trên nền biển.
struct AppGlassBarBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    AppTheme.oceanDeep.opacity(0.55),
                    AppTheme.oceanAbyss.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [
                    AppTheme.specularLine.opacity(0.42),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

final class ClearHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        super.loadView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.isOpaque = false
        view.autoresizingMask = [.width, .height]
    }
}

typealias GlassHostingController = ClearHostingController
