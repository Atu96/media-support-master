import AppKit
import SwiftUI

private enum SubtitleStyleInspectorPage: String, CaseIterable, Identifiable {
    case design
    case effects

    var id: String { rawValue }
    var localizationKey: String { self == .design ? "Thiết kế" : "Hiệu ứng" }
}

/// Header cố định của Inspector «Kiểu sub».
struct SubtitleBurnStylePanelHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .fill(AppTheme.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                            .strokeBorder(AppTheme.tileStroke, lineWidth: AppTheme.hairlineWidth)
                    }
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBlue)
            }
            .frame(width: 38, height: 38)

            Text("Kiểu sub")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            Spacer(minLength: 0)
        }
    }
}

struct SubtitleBurnStylePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var style: SubtitleBurnStyle
    /// Chữ/dòng — rule tạo sub + ngắt từng cue (1/2 dòng).
    @Binding var maxCharsPerLine: Int
    /// Chế độ sau chép lời: 1 hoặc 2 dòng/cue.
    @Binding var maxLines: Int
    var onAutoMaxChars: () -> Void = {}
    var canBurn: Bool
    var isRunning: Bool
    var statusMessage: String = ""
    var onBurn: () -> Void
    var isApplyingLayout = false
    /// Khi nằm trong slide, header được đặt cố định bên ngoài vùng cuộn.
    var showsHeader = true
    /// Workspace Timeline gom xuất video vào menu trên header để tránh lặp hành động.
    var showsExportControls = true
    @State private var textExpanded = true
    @State private var layoutExpanded = true
    @State private var backgroundExpanded = false
    @State private var outlineExpanded = false
    @State private var shadowExpanded = false
    @State private var exportExpanded = false
    @State private var inspectorPage: SubtitleStyleInspectorPage = .design
    @State private var effectFineTuneExpanded = true
    @State private var fontSuggestionsExpanded = false

    private let fpsOptions = ["24", "25", "30", "60"]
    private let subtitleSizePresets = [36, 45, 54, 63]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                SubtitleBurnStylePanelHeader()
            }

            Picker("", selection: $inspectorPage) {
                ForEach(SubtitleStyleInspectorPage.allCases) { page in
                    Text(L10n.string(page.localizationKey)).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 2)
            .accessibilityLabel(L10n.string("Trang kiểu phụ đề"))

            if inspectorPage == .design {
                quickPresetSection

                collapsibleSection(title: "Chữ", icon: "textformat", isExpanded: $textExpanded) {
                compactRow("Font") {
                    LocalFontPickerButton(fontName: $style.fontName)
                        .frame(maxWidth: .infinity)
                }
                compactRow("Cỡ nhanh") {
                    HStack(spacing: 2) {
                        HStack(spacing: 4) {
                            ForEach(subtitleSizePresets, id: \.self) { size in
                                sizePresetButton(size)
                            }
                        }
                        Text("pt")
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: 20, alignment: .leading)
                    }
                }
                compactRow("Cỡ chữ") {
                    intField(value: $style.fontSize, range: 18...96, suffix: "pt")
                        .frame(width: 106)
                }
                compactColorRow("Màu chữ", hex: $style.textColorHex)
            }

                collapsibleSection(title: "Bố cục", icon: "rectangle.split.2x1", isExpanded: $layoutExpanded) {
                compactRow("Chữ / dòng") {
                    HStack(spacing: 6) {
                        intField(value: $maxCharsPerLine, range: 12...80, suffix: nil)
                            .frame(width: 78)
                        Button("Tự động", action: onAutoMaxChars)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Tính lại chữ/dòng theo ngôn ngữ và cỡ chữ hiện tại")
                    }
                }
                compactRow("Dòng / cue") {
                    Picker("", selection: $maxLines) {
                        Text("1 dòng").tag(1)
                        Text("2 dòng").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 142)
                    .help(L10n.string("Đổi bố cục phụ đề hiện có và áp dụng cho lần chép lời tiếp theo."))
                }
                if isApplyingLayout {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.string("Đang sắp xếp phụ đề…"))
                            .font(AppFont.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .accessibilityElement(children: .combine)
                }
                compactSliderRow("Lề đáy", value: Binding(
                    get: { Double(style.marginBottom) },
                    set: { style.marginBottom = Int($0) }
                ), range: 16...120, format: "%.0f px") {
                    "\(style.marginBottom) px"
                }
            }

                toggleableSection(
                title: "Nền chữ",
                icon: "rectangle.fill",
                isEnabled: $style.boxEnabled,
                isExpanded: $backgroundExpanded
            ) {
                compactColorRow("Màu nền", hex: $style.boxColorHex)
                compactSliderRow("Độ trong suốt", value: $style.boxOpacity, range: 0...1, format: "%.0f%%") {
                    "\(Int(style.boxOpacity * 100))%"
                }
                compactSliderRow(
                    "Bo góc",
                    value: Binding(
                        get: { Double(style.boxCornerRadius) },
                        set: {
                            let r = SubtitleBurnStyle.boxCornerRadiusRange
                            style.boxCornerRadius = min(r.upperBound, max(r.lowerBound, Int($0.rounded())))
                        }
                    ),
                    range: 0...24,
                    format: "%.0f px"
                ) {
                    "\(style.boxCornerRadius) px"
                }
                compactSliderRow(
                    "Độ rộng",
                    value: Binding(
                        get: { Double(style.boxMaxWidthPercent) },
                        set: {
                            let r = SubtitleBurnStyle.boxMaxWidthPercentRange
                            style.boxMaxWidthPercent = min(r.upperBound, max(r.lowerBound, Int($0.rounded())))
                        }
                    ),
                    range: 40...100,
                    format: "%.0f%%"
                ) {
                    "\(style.boxMaxWidthPercent)% khung hình"
                }
            }

                toggleableSection(
                title: "Viền",
                icon: "circle.dashed",
                isEnabled: $style.outlineEnabled,
                isExpanded: $outlineExpanded
            ) {
                compactColorRow("Màu viền", hex: $style.outlineColorHex)
                compactRow("Độ dày") {
                    intField(value: $style.outlineWidth, range: 0...12, suffix: "px")
                        .frame(width: 106)
                }
                compactSliderRow("Độ đậm", value: $style.outlineOpacity, range: 0...1, format: "%.0f%%") {
                    "\(Int(style.outlineOpacity * 100))%"
                }
            }

                toggleableSection(
                title: "Bóng đổ",
                icon: "drop.fill",
                isEnabled: $style.shadowEnabled,
                isExpanded: $shadowExpanded
            ) {
                compactColorRow("Màu bóng", hex: $style.shadowColorHex)
                compactSliderRow("Độ đậm", value: $style.shadowOpacity, range: 0...1, format: "%.0f%%") {
                    "\(Int(style.shadowOpacity * 100))%"
                }
                compactRow("Độ mờ") { intField(value: $style.shadowBlur, range: 0...20, suffix: "px").frame(width: 106) }
                compactRow("Khoảng cách") { intField(value: $style.shadowDistance, range: 0...30, suffix: "px").frame(width: 106) }
                compactRow("Góc") { intField(value: $style.shadowAngle, range: 0...360, suffix: "°").frame(width: 106) }
            }

            } else {
                effectsPage
            }

            if showsExportControls {
                collapsibleSection(title: "Xuất", icon: "square.and.arrow.up", isExpanded: $exportExpanded) {
                    compactRow("FPS XML") {
                        Picker("", selection: $style.fps) {
                            ForEach(fpsOptions, id: \.self) { fps in
                                Text(fps).tag(fps)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 106, alignment: .leading)
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.accentGreen)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                }

                AppPillButton(
                    title: isRunning ? "Đang xuất…" : "Xuất video",
                    icon: "film.stack.fill",
                    tint: AppTheme.accentGreen,
                    filled: true,
                    disabled: !canBurn || isRunning
                ) {
                    style.save()
                    onBurn()
                }
                .frame(maxWidth: .infinity)
                .overlay {
                    BurnActionButtonAnchorReporter()
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(8)
        // Neo toàn khung (mép trên + trái) cho NSFontPanel / NSColorPanel.
        .background {
            BurnPanelFrameAnchorReporter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .onChange(of: style) { _, newValue in
            newValue.save()
        }
        .onAppear {
            // Danh sách FPS được giản lược; project cũ có 48/2997/2398 về mặc định 24.
            if !fpsOptions.contains(style.fps) {
                style.fps = "24"
            }
        }
    }

    private var effectsPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Hiệu ứng phụ đề nhạc", systemImage: "music.note.list")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.headlineText)
                Text("Hiển thị trong app và video xuất. FCPXML vẫn giữ phụ đề chuẩn, sạch hiệu ứng.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))

            effectChoiceGroup(title: "Chuyển cảnh chữ", icon: "rectangle.on.rectangle.angled") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(SubtitleTextTransition.allCases) { transition in
                        transitionCard(transition)
                    }
                }
            }

            effectChoiceGroup(title: "Phong cách hiệu ứng", icon: "wand.and.stars") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(SubtitleVisualEffect.allCases) { effect in
                        visualEffectCard(effect)
                    }
                }
            }

            collapsibleSection(
                title: "Font gợi ý",
                icon: "textformat.alt",
                isExpanded: $fontSuggestionsExpanded
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(suggestedFonts, id: \.name) { item in
                        Button {
                            style.fontName = item.name
                        } label: {
                            Text(item.label)
                                .font(.custom(item.name, size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    style.fontName == item.name
                                        ? AppTheme.accentBlue.opacity(0.18)
                                        : AppTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                        }
                        .buttonStyle(AppPressableButtonStyle())
                        .help(item.label)
                    }
                }
            }

            collapsibleSection(
                title: "Tinh chỉnh",
                icon: "slider.horizontal.3",
                isExpanded: $effectFineTuneExpanded
            ) {
                compactSliderRow("Cường độ", value: $style.effectIntensity, range: 0.1...1, format: "%.0f%%") {
                    "\(Int(style.effectIntensity * 100))%"
                }
                compactSliderRow("Tốc độ", value: $style.effectSpeed, range: 0.5...2, format: "%.1fx") {
                    String(format: "%.1fx", style.effectSpeed)
                }
                if style.visualEffect == .starlight || style.visualEffect == .butterflyTrail {
                    compactRow("Mật độ") {
                        intField(value: $style.effectDensity, range: 2...18, suffix: nil)
                            .frame(width: 106)
                    }
                    compactColorRow("Màu hiệu ứng", hex: $style.effectColorHex)
                } else if style.visualEffect == .goldenSweep || style.visualEffect == .neonAura {
                    compactColorRow("Màu hiệu ứng", hex: $style.effectColorHex)
                }

            }
        }
    }

    private func effectChoiceGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L10n.string(title), systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
            content()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
    }

    private func transitionCard(_ transition: SubtitleTextTransition) -> some View {
        let selected = style.textTransition == transition
        return Button {
            style.textTransition = transition
            // Transition nhạc tự mang ngôn ngữ chuyển động riêng. Không phủ
            // fade dùng chung vì sẽ làm mọi preset trông giống nhau.
            style.fadeInEnabled = false
            style.fadeOutEnabled = false
            NotificationCenter.default.post(name: .msmSubtitleStylePresetPreviewRequested, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: transition.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : transitionTint(transition))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(transition.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .white : AppTheme.bodyText)
                        .lineLimit(1)
                    Text(L10n.string(transition.descriptionLocalizationKey))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : AppTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 52)
            .background(
                selected ? AppTheme.accentBlue : transitionTint(transition).opacity(colorScheme == .dark ? 0.12 : 0.09),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.28) : sectionStroke, lineWidth: AppTheme.hairlineWidth)
            }
        }
        .buttonStyle(AppPressableButtonStyle())
        .help(L10n.format("Chọn hiệu ứng %@", L10n.string(transition.localizationKey)))
        .accessibilityLabel(L10n.string(transition.localizationKey))
        .accessibilityHint(L10n.string(transition.descriptionLocalizationKey))
    }

    private func visualEffectCard(_ effect: SubtitleVisualEffect) -> some View {
        let selected = style.visualEffect == effect
        return Button {
            style.visualEffect = effect
            style.fadeInEnabled = false
            style.fadeOutEnabled = false
            switch effect {
            case .none: break
            case .goldenSweep: style.effectColorHex = "#FFD66B"
            case .neonAura: style.effectColorHex = "#37D7FF"
            case .starlight:
                style.effectColorHex = "#B7A8FF"
                style.effectDensity = 8
            case .butterflyTrail:
                style.effectColorHex = "#62E6BE"
                style.effectDensity = 12
            }
            NotificationCenter.default.post(name: .msmSubtitleStylePresetPreviewRequested, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: effect.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : visualEffectTint(effect))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(effect.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .white : AppTheme.bodyText)
                        .lineLimit(1)
                    Text(L10n.string(effect.descriptionLocalizationKey))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : AppTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 52)
            .background(
                selected ? AppTheme.accentBlue : visualEffectTint(effect).opacity(colorScheme == .dark ? 0.12 : 0.09),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.28) : sectionStroke, lineWidth: AppTheme.hairlineWidth)
            }
        }
        .buttonStyle(AppPressableButtonStyle())
        .help(L10n.format("Chọn hiệu ứng %@", L10n.string(effect.localizationKey)))
        .accessibilityLabel(L10n.string(effect.localizationKey))
        .accessibilityHint(L10n.string(effect.descriptionLocalizationKey))
    }

    private func transitionTint(_ transition: SubtitleTextTransition) -> Color {
        switch transition {
        case .none: AppTheme.mutedText
        case .leftToRight: Color(red: 0.37, green: 0.70, blue: 1)
        case .rightToLeft: Color(red: 0.42, green: 0.62, blue: 1)
        case .bottomUp: Color(red: 0.32, green: 0.78, blue: 0.92)
        case .softPop: Color(red: 0.76, green: 0.42, blue: 1)
        case .wordByWord: Color(red: 0.34, green: 0.82, blue: 0.64)
        }
    }

    private func visualEffectTint(_ effect: SubtitleVisualEffect) -> Color {
        switch effect {
        case .none: AppTheme.mutedText
        case .goldenSweep: Color(red: 1, green: 0.72, blue: 0.22)
        case .neonAura: Color(red: 0.20, green: 0.86, blue: 0.96)
        case .starlight: Color(red: 0.65, green: 0.56, blue: 1)
        case .butterflyTrail: Color(red: 0.28, green: 0.86, blue: 0.72)
        }
    }

    private var suggestedFonts: [(name: String, label: String)] {
        [
            ("AvenirNext-DemiBold", "Avenir Next"),
            ("Futura-Medium", "Futura"),
            ("Optima-Bold", "Optima"),
            ("HoeflerText-Black", "Hoefler Text"),
            ("PingFangSC-Semibold", "PingFang"),
            ("HiraginoSans-W6", "Hiragino Sans"),
        ].filter { NSFont(name: $0.name, size: 12) != nil }
    }

    private var quickPresetSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Mẫu nhanh", systemImage: "rectangle.3.group.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
            presetRow
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(sectionFill, in: RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                .strokeBorder(sectionStroke, lineWidth: AppTheme.hairlineWidth)
        }
    }

    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isExpanded.wrappedValue ? 5 : 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                    Text(L10n.string(title))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .foregroundStyle(AppTheme.headlineText)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPlainButtonStyle())

            if isExpanded.wrappedValue {
                sectionDivider
                content()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(sectionFill, in: RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                .strokeBorder(sectionStroke, lineWidth: AppTheme.hairlineWidth)
        }
    }

    private func toggleableSection<Content: View>(
        title: String,
        icon: String,
        isEnabled: Binding<Bool>,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: isExpanded.wrappedValue ? 5 : 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    let willOpen = !isExpanded.wrappedValue
                    isExpanded.wrappedValue = willOpen
                    isEnabled.wrappedValue = willOpen
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isEnabled.wrappedValue ? AppTheme.accentBlue : AppTheme.mutedText
                        )
                        .frame(width: 17)
                    Text(L10n.string(title))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .foregroundStyle(AppTheme.headlineText)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPlainButtonStyle())
            .help(isExpanded.wrappedValue
                ? L10n.format("Thu gọn và tắt %@", L10n.string(title))
                : L10n.format("Mở và bật %@", L10n.string(title)))

            if isExpanded.wrappedValue {
                sectionDivider
                content()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(sectionFill, in: RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                .strokeBorder(sectionStroke, lineWidth: AppTheme.hairlineWidth)
        }
    }

    private var sectionFill: Color {
        colorScheme == .dark
            ? AppTheme.inputFill.opacity(0.62)
            : AppTheme.tileFill.opacity(0.68)
    }

    private var sectionStroke: Color {
        colorScheme == .dark
            ? AppTheme.tileStroke.opacity(0.58)
            : AppTheme.tileStroke.opacity(0.72)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(height: AppTheme.hairlineWidth)
    }

    private var presetRow: some View {
        HStack(spacing: 7) {
            presetButton("Đen / trắng", text: "#000000", box: "#FFFFFF", boxEnabled: true, outline: false)
            presetButton("Trắng / đen", text: "#FFFFFF", box: "#000000", boxEnabled: true, outline: false)
            presetButton("Chữ viền", text: "#FFFFFF", box: "#000000", boxEnabled: false, outline: true)
        }
    }

    private func sizePresetButton(_ size: Int) -> some View {
        Button {
            style.fontSize = size
        } label: {
            Text("\(size)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.fontSize == size ? .white : AppTheme.accentBlue)
                .frame(width: 25, height: 23)
                .background(
                    style.fontSize == size ? AppTheme.accentBlue : AppTheme.accentBlue.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(AppPressableButtonStyle())
        .help("\(size) pt")
    }

    private func presetButton(
        _ title: String,
        text: String,
        box: String,
        boxEnabled: Bool,
        outline: Bool
    ) -> some View {
        Button {
            style.textColorHex = text
            style.boxColorHex = box
            style.boxEnabled = boxEnabled
            style.boxOpacity = boxEnabled ? 0.9 : 0
            style.outlineEnabled = outline
            style.outlineColorHex = "#000000"
            style.outlineOpacity = 1
            style.outlineWidth = 3
            style.shadowEnabled = false
            if outline {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    backgroundExpanded = false
                    outlineExpanded = true
                }
            }
        } label: {
            Text(L10n.string(title))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(AppTheme.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(AppPressableButtonStyle())
    }

    /// Hàng inspector thanh mảnh: nhãn thẳng cột, control nằm sát sau nhãn.
    private func compactRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 9) {
            Text(L10n.string(label))
                .font(AppFont.editorBody)
                .foregroundStyle(AppTheme.bodyText)
                .frame(width: 92, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 29)
    }

    private func compactColorRow(_ label: String, hex: Binding<String>) -> some View {
        compactRow(label) {
            LocalColorPickerButton(hex: hex)
                .frame(width: 106, alignment: .leading)
        }
    }

    private func compactSliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        display: () -> String
    ) -> some View {
        HStack(spacing: 9) {
            Text(L10n.string(label))
                .font(AppFont.editorBody)
                .foregroundStyle(AppTheme.bodyText)
                .frame(width: 92, alignment: .leading)
            SubtitleStyleGlassSlider(value: value, range: range)
                .frame(height: 22)
            Text(display())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 54, alignment: .trailing)
        }
        .frame(minHeight: 29)
    }

    /// Bấm vào ô → gõ số trực tiếp (nhanh hơn stepper).
    private func intField(value: Binding<Int>, range: ClosedRange<Int>, suffix: String?) -> some View {
        HStack(spacing: 4) {
            TextField(
                "",
                text: Binding(
                    get: { String(value.wrappedValue) },
                    set: { raw in
                        let digits = raw.filter(\.isNumber)
                        guard let n = Int(digits), !digits.isEmpty else { return }
                        value.wrappedValue = min(range.upperBound, max(range.lowerBound, n))
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(AppFont.body)
            // Ô số luôn cùng bề rộng; đơn vị có cột riêng nên 64 pt không làm ngắn
            // ô nhập so với 33 hay các ô px/° kế bên.
            .frame(width: 78)
            .multilineTextAlignment(.leading)
            #if os(macOS)
            .onSubmit { }
            #endif
            if let suffix {
                Text(suffix)
                    .font(AppFont.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 20, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: 20)
            }
        }
    }

}

/// Cùng ngôn ngữ với thanh kéo preview: track mảnh xanh + núm glass trắng.
struct SubtitleStyleGlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let progress = min(1, max(0, (value - range.lowerBound) / span))
            let x = progress * width
            let trackHeight: CGFloat = 4
            let thumb: CGFloat = 16

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accentBlue, AppTheme.accentBlue.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumb / 2, x), height: trackHeight)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: thumb, height: thumb)
                    .overlay {
                        Circle().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.88), Color.white.opacity(0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: max(0, min(width - thumb, x - thumb / 2)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(1, max(0, gesture.location.x / width))
                        value = range.lowerBound + span * fraction
                    }
            )
        }
        .accessibilityValue(Text("\(Int(value.rounded()))"))
    }
}
