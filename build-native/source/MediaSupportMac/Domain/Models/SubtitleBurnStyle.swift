import AppKit
import Foundation
import SwiftUI

enum SubtitleEffectPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case softFade
    case gentleFloat
    case softSlide
    case softPop
    case lightSweep
    case fairyDust
    case butterfly

    /// Bộ preset cao cấp hiển thị trong UI. `softSlide` được giữ để đọc project cũ,
    /// nhưng được migrate sang Cinema Reveal khi decode.
    static let allCases: [SubtitleEffectPreset] = [
        .none,
        .softFade,
        .softPop,
        .lightSweep,
        .gentleFloat,
        .fairyDust,
        .butterfly,
    ]

    var id: String { rawValue }

    /// FCPXML chỉ giữ hiệu ứng subtitle chuẩn. Các preset còn lại là renderer độc quyền của app.
    var isAppExclusive: Bool {
        self != .none
    }

    var localizationKey: String {
        switch self {
        case .none: "Không hiệu ứng"
        case .softFade: "Cinema Reveal"
        case .gentleFloat: "Neon Aura"
        case .softSlide: "Trượt mềm"
        case .softPop: "Dream Pop"
        case .lightSweep: "Golden Sweep"
        case .fairyDust: "Tinh quang"
        case .butterfly: "Butterfly Trail"
        }
    }

    var descriptionLocalizationKey: String {
        switch self {
        case .none: "Chữ tĩnh, rõ ràng"
        case .softFade: "Mở chữ theo nhịp điện ảnh"
        case .gentleFloat: "Viền neon thở có chiều sâu"
        case .softSlide: "Trượt theo hướng đã chọn"
        case .softPop: "Bung spring rồi ổn định"
        case .lightSweep: "Dải sáng vàng chạy trên chữ"
        case .fairyDust: "Tinh quang bám quanh mép chữ"
        case .butterfly: "Cánh bay theo cung và để lại sáng"
        }
    }

    var symbolName: String {
        switch self {
        case .none: "circle.slash"
        case .softFade: "text.line.first.and.arrowtriangle.forward"
        case .gentleFloat: "light.beacon.max.fill"
        case .softSlide: "arrow.right"
        case .softPop: "circle.hexagongrid.fill"
        case .lightSweep: "sun.max.trianglebadge.exclamationmark"
        case .fairyDust: "staroflife.fill"
        case .butterfly: "butterfly.fill"
        }
    }
}

/// Chuyển động đưa toàn bộ Text Group vào/ra. Tách khỏi trang trí để người dùng
/// có thể phối một chuyển cảnh với bất kỳ phong cách ánh sáng nào mà không tạo
/// hàng chục preset trùng lặp.
enum SubtitleTextTransition: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case leftToRight
    case rightToLeft
    case bottomUp
    case softPop
    case wordByWord

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .none: "Không chuyển cảnh"
        case .leftToRight: "Trái → phải"
        case .rightToLeft: "Phải → trái"
        case .bottomUp: "Dưới → lên"
        case .softPop: "Nảy nhẹ"
        case .wordByWord: "Theo từng từ"
        }
    }

    var descriptionLocalizationKey: String {
        switch self {
        case .none: "Hiện nguyên câu"
        case .leftToRight: "Mở chữ tự nhiên theo chiều đọc"
        case .rightToLeft: "Mở chữ từ mép phải"
        case .bottomUp: "Nâng cả nhóm chữ lên nhẹ"
        case .softPop: "Bung spring rồi ổn định"
        case .wordByWord: "Hiện lần lượt theo nhịp từ"
        }
    }

    var symbolName: String {
        switch self {
        case .none: "circle.slash"
        case .leftToRight: "text.line.first.and.arrowtriangle.forward"
        case .rightToLeft: "text.line.last.and.arrowtriangle.forward"
        case .bottomUp: "arrow.up"
        case .softPop: "circle.hexagongrid.fill"
        case .wordByWord: "text.word.spacing"
        }
    }
}

/// Phong cách thị giác chạy bên trong cùng Text Group với nền và chữ.
enum SubtitleVisualEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case goldenSweep
    case neonAura
    case starlight
    case butterflyTrail

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .none: "Không trang trí"
        case .goldenSweep: "Golden Sweep"
        case .neonAura: "Neon Aura"
        case .starlight: "Tinh quang"
        case .butterflyTrail: "Butterfly Trail"
        }
    }

    var descriptionLocalizationKey: String {
        switch self {
        case .none: "Giữ chữ sạch và tập trung"
        case .goldenSweep: "Dải sáng vàng chạy trên chữ"
        case .neonAura: "Viền neon thở có chiều sâu"
        case .starlight: "Tinh quang bám quanh mép chữ"
        case .butterflyTrail: "Cánh bay theo cung và để lại sáng"
        }
    }

    var symbolName: String {
        switch self {
        case .none: "circle.slash"
        case .goldenSweep: "sun.max.trianglebadge.exclamationmark"
        case .neonAura: "light.beacon.max.fill"
        case .starlight: "staroflife.fill"
        case .butterflyTrail: "butterfly.fill"
        }
    }
}

enum SubtitleEffectDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case up
    case left
    case right

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .up: "Lên trên"
        case .left: "Từ trái"
        case .right: "Từ phải"
        }
    }
}

struct SubtitleBurnStyle: Codable, Equatable, Sendable {
    /// Mặc định khớp `convert_srt_fcpxml.py` (template «Phu de nen den»).
    var fontName = "PingFang SC"
    var fontSize = 54
    private static let defaultsBumpKey = "msm.subtitleBurnStyle.defaultsBump.v54"
    var textColorHex = "#FFFFFF"
    var boxEnabled = true
    var boxOpacity = 0.9
    var boxColorHex = "#000000"
    /// Độ bo góc hộp nền (text box) trên preview — px @1080p. Chỉ panel burn; không đụng AppTheme.
    var boxCornerRadius = 6
    /// Độ dài tối đa text box — % bề ngang khung video (trước đây hardcode 92%).
    var boxMaxWidthPercent = 92
    var outlineEnabled = false
    var outlineColorHex = "#000000"
    var outlineOpacity = 1.0
    var outlineWidth = 3
    var shadowEnabled = false
    var shadowColorHex = "#000000"
    var shadowOpacity = 0.75
    var shadowBlur = 0
    var shadowDistance = 5
    var shadowAngle = 315
    // Fade được giữ để đọc project/subtitle chuẩn cũ. Hiệu ứng nhạc app-only
    // không dùng opacity fade; transition phải tự thể hiện bằng silhouette riêng.
    var fadeInEnabled = false
    var fadeOutEnabled = false
    var fadeInMs = 200
    var fadeOutMs = 200
    /// Hiệu ứng nhạc: transition và decoration độc lập nhưng cùng chạy trên một Text Group.
    /// FCPXML chủ động bỏ qua cả hai vì đây là renderer độc quyền của app.
    var textTransition: SubtitleTextTransition = .leftToRight
    var visualEffect: SubtitleVisualEffect = .none
    var effectIntensity = 0.68
    var effectSpeed = 1.0
    var effectDirection: SubtitleEffectDirection = .up
    var effectDensity = 8
    var effectColorHex = "#8FD3FF"
    var marginBottom = 48
    var fcpxmlPositionY = -414
    var fps = "24"

    static let storageKey = "msm.subtitleBurnStyle"
    /// Phạm vi slider panel «Gắn sub vào video».
    static let boxCornerRadiusRange = 0...24
    static let boxMaxWidthPercentRange = 40...100

    /// Cầu nối source/project cũ. Code mới phải dùng `textTransition` và
    /// `visualEffect`; setter này chỉ phục vụ migration/test tương thích.
    var effectPreset: SubtitleEffectPreset {
        get {
            switch visualEffect {
            case .goldenSweep: return .lightSweep
            case .neonAura: return .gentleFloat
            case .starlight: return .fairyDust
            case .butterflyTrail: return .butterfly
            case .none:
                switch textTransition {
                case .none: return .none
                case .softPop: return .softPop
                case .leftToRight, .rightToLeft, .bottomUp, .wordByWord: return .softFade
                }
            }
        }
        set { applyLegacyEffectPreset(newValue) }
    }

    var hasAppExclusiveEffects: Bool {
        textTransition != .none || visualEffect != .none
    }

    /// Tương thích code/preset cũ; UI mới điều khiển từng phía độc lập.
    var fadeEnabled: Bool {
        get { fadeInEnabled || fadeOutEnabled }
        set {
            fadeInEnabled = newValue
            fadeOutEnabled = newValue
        }
    }

    /// Tỷ lệ maxWidth preview (0.40…1.0).
    var boxMaxWidthRatio: CGFloat {
        CGFloat(min(
            Self.boxMaxWidthPercentRange.upperBound,
            max(Self.boxMaxWidthPercentRange.lowerBound, boxMaxWidthPercent)
        )) / 100
    }

    /// Một nguồn timing cho reveal ở Preview và video native.
    /// Phần chữ đã hé luôn opaque; duration này chỉ điều khiển mép mask.
    func transitionEntranceDuration(forCueDuration cueDuration: Double) -> Double {
        let safeDuration = max(0.08, cueDuration)
        let preferred = max(0.22, 0.56 / max(effectSpeed, 0.5))
        return min(safeDuration * 0.48, preferred)
    }

    /// Golden Sweep chạy đúng một lượt trên glyph, không lặp và không làm mờ cả group.
    func goldenSweepTiming(forCueDuration cueDuration: Double) -> (delay: Double, duration: Double) {
        let safeDuration = max(0.08, cueDuration)
        let baseDelay = min(0.12, safeDuration * 0.08)
        let revealHasMotion = textTransition != .none
        let postRevealDelay = transitionEntranceDuration(forCueDuration: safeDuration)
            + min(0.08, safeDuration * 0.02)
        // Khi có chuyển cảnh, đợi wipe/pop hoàn tất rồi mới quét vàng.
        // Hai chuyển động nối tiếp nên mắt nhìn rõ cả hướng lộ chữ lẫn chất liệu Golden.
        let delay = min(safeDuration * 0.46, revealHasMotion ? postRevealDelay : baseDelay)
        let available = max(0.04, safeDuration - delay)
        let preferred = max(0.48, 0.92 / max(effectSpeed, 0.5))
        return (delay, min(available * 0.82, preferred))
    }

    static func load() -> SubtitleBurnStyle {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey),
              var style = try? JSONDecoder().decode(SubtitleBurnStyle.self, from: data) else {
            defaults.set(true, forKey: defaultsBumpKey)
            return SubtitleBurnStyle()
        }
        // Default cũ 63 → 54 (một lần). Giữ nếu user đã chọn cỡ khác.
        if !defaults.bool(forKey: defaultsBumpKey) {
            defaults.set(true, forKey: defaultsBumpKey)
            if style.fontSize == 63 {
                style.fontSize = 54
                style.save()
            }
        }
        style.boxCornerRadius = min(
            Self.boxCornerRadiusRange.upperBound,
            max(Self.boxCornerRadiusRange.lowerBound, style.boxCornerRadius)
        )
        style.boxMaxWidthPercent = min(
            Self.boxMaxWidthPercentRange.upperBound,
            max(Self.boxMaxWidthPercentRange.lowerBound, style.boxMaxWidthPercent)
        )
        style.outlineOpacity = min(1, max(0, style.outlineOpacity))
        style.outlineWidth = min(12, max(0, style.outlineWidth))
        style.shadowOpacity = min(1, max(0, style.shadowOpacity))
        style.shadowBlur = min(20, max(0, style.shadowBlur))
        style.shadowDistance = min(30, max(0, style.shadowDistance))
        style.shadowAngle = min(360, max(0, style.shadowAngle))
        style.effectIntensity = min(1, max(0.1, style.effectIntensity))
        style.effectSpeed = min(2, max(0.5, style.effectSpeed))
        style.effectDensity = min(18, max(2, style.effectDensity))
        return style
    }

    enum CodingKeys: String, CodingKey {
        case fontName, fontSize, textColorHex
        case boxEnabled, boxOpacity, boxColorHex, boxCornerRadius, boxMaxWidthPercent
        case outlineEnabled, outlineColorHex, outlineOpacity, outlineWidth
        case shadowEnabled, shadowColorHex, shadowOpacity, shadowBlur, shadowDistance, shadowAngle
        case fadeEnabled, fadeInEnabled, fadeOutEnabled, fadeInMs, fadeOutMs
        case effectPreset, textTransition, visualEffect
        case effectIntensity, effectSpeed, effectDirection, effectDensity, effectColorHex
        case marginBottom, fcpxmlPositionY, fps
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "PingFang SC"
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? 54
        textColorHex = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FFFFFF"
        boxEnabled = try c.decodeIfPresent(Bool.self, forKey: .boxEnabled) ?? true
        boxOpacity = try c.decodeIfPresent(Double.self, forKey: .boxOpacity) ?? 0.9
        boxColorHex = try c.decodeIfPresent(String.self, forKey: .boxColorHex) ?? "#000000"
        // Key mới — decodeIfPresent để không reset style user cũ.
        boxCornerRadius = try c.decodeIfPresent(Int.self, forKey: .boxCornerRadius) ?? 6
        boxMaxWidthPercent = try c.decodeIfPresent(Int.self, forKey: .boxMaxWidthPercent) ?? 92
        outlineEnabled = try c.decodeIfPresent(Bool.self, forKey: .outlineEnabled) ?? false
        outlineColorHex = try c.decodeIfPresent(String.self, forKey: .outlineColorHex) ?? "#000000"
        outlineOpacity = try c.decodeIfPresent(Double.self, forKey: .outlineOpacity) ?? 1
        outlineWidth = try c.decodeIfPresent(Int.self, forKey: .outlineWidth) ?? 3
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? false
        shadowColorHex = try c.decodeIfPresent(String.self, forKey: .shadowColorHex) ?? "#000000"
        shadowOpacity = try c.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.75
        shadowBlur = try c.decodeIfPresent(Int.self, forKey: .shadowBlur) ?? 0
        shadowDistance = try c.decodeIfPresent(Int.self, forKey: .shadowDistance) ?? 5
        shadowAngle = try c.decodeIfPresent(Int.self, forKey: .shadowAngle) ?? 315
        let legacyFade = try c.decodeIfPresent(Bool.self, forKey: .fadeEnabled) ?? true
        fadeInEnabled = try c.decodeIfPresent(Bool.self, forKey: .fadeInEnabled) ?? legacyFade
        fadeOutEnabled = try c.decodeIfPresent(Bool.self, forKey: .fadeOutEnabled) ?? legacyFade
        fadeInMs = try c.decodeIfPresent(Int.self, forKey: .fadeInMs) ?? 200
        fadeOutMs = try c.decodeIfPresent(Int.self, forKey: .fadeOutMs) ?? 200
        if let transition = try c.decodeIfPresent(SubtitleTextTransition.self, forKey: .textTransition) {
            textTransition = transition
            visualEffect = try c.decodeIfPresent(SubtitleVisualEffect.self, forKey: .visualEffect) ?? .none
        } else {
            let legacyPreset = try c.decodeIfPresent(SubtitleEffectPreset.self, forKey: .effectPreset)
                ?? ((fadeInEnabled || fadeOutEnabled) ? .softFade : .none)
            applyLegacyEffectPreset(legacyPreset)
        }
        effectIntensity = try c.decodeIfPresent(Double.self, forKey: .effectIntensity) ?? 0.68
        effectSpeed = try c.decodeIfPresent(Double.self, forKey: .effectSpeed) ?? 1
        effectDirection = try c.decodeIfPresent(SubtitleEffectDirection.self, forKey: .effectDirection) ?? .up
        effectDensity = try c.decodeIfPresent(Int.self, forKey: .effectDensity) ?? 8
        effectColorHex = try c.decodeIfPresent(String.self, forKey: .effectColorHex) ?? "#8FD3FF"
        marginBottom = try c.decodeIfPresent(Int.self, forKey: .marginBottom) ?? 48
        fcpxmlPositionY = try c.decodeIfPresent(Int.self, forKey: .fcpxmlPositionY) ?? -414
        fps = try c.decodeIfPresent(String.self, forKey: .fps) ?? "24"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fontName, forKey: .fontName)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(textColorHex, forKey: .textColorHex)
        try c.encode(boxEnabled, forKey: .boxEnabled)
        try c.encode(boxOpacity, forKey: .boxOpacity)
        try c.encode(boxColorHex, forKey: .boxColorHex)
        try c.encode(boxCornerRadius, forKey: .boxCornerRadius)
        try c.encode(boxMaxWidthPercent, forKey: .boxMaxWidthPercent)
        try c.encode(outlineEnabled, forKey: .outlineEnabled)
        try c.encode(outlineColorHex, forKey: .outlineColorHex)
        try c.encode(outlineOpacity, forKey: .outlineOpacity)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(shadowColorHex, forKey: .shadowColorHex)
        try c.encode(shadowOpacity, forKey: .shadowOpacity)
        try c.encode(shadowBlur, forKey: .shadowBlur)
        try c.encode(shadowDistance, forKey: .shadowDistance)
        try c.encode(shadowAngle, forKey: .shadowAngle)
        try c.encode(fadeEnabled, forKey: .fadeEnabled)
        try c.encode(fadeInEnabled, forKey: .fadeInEnabled)
        try c.encode(fadeOutEnabled, forKey: .fadeOutEnabled)
        try c.encode(fadeInMs, forKey: .fadeInMs)
        try c.encode(fadeOutMs, forKey: .fadeOutMs)
        try c.encode(textTransition, forKey: .textTransition)
        try c.encode(visualEffect, forKey: .visualEffect)
        try c.encode(effectIntensity, forKey: .effectIntensity)
        try c.encode(effectSpeed, forKey: .effectSpeed)
        try c.encode(effectDirection, forKey: .effectDirection)
        try c.encode(effectDensity, forKey: .effectDensity)
        try c.encode(effectColorHex, forKey: .effectColorHex)
        try c.encode(marginBottom, forKey: .marginBottom)
        try c.encode(fcpxmlPositionY, forKey: .fcpxmlPositionY)
        try c.encode(fps, forKey: .fps)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private mutating func applyLegacyEffectPreset(_ preset: SubtitleEffectPreset) {
        switch preset {
        case .none:
            textTransition = .none
            visualEffect = .none
        case .softFade, .softSlide:
            textTransition = .leftToRight
            visualEffect = .none
        case .softPop:
            textTransition = .softPop
            visualEffect = .none
        case .lightSweep:
            textTransition = .none
            visualEffect = .goldenSweep
        case .gentleFloat:
            textTransition = .none
            visualEffect = .neonAura
        case .fairyDust:
            textTransition = .none
            visualEffect = .starlight
        case .butterfly:
            textTransition = .none
            visualEffect = .butterflyTrail
        }
    }

    var fontColorRGBA: String {
        Self.hexToRGBA(textColorHex)
    }

    var fcpxmlFontColor: String {
        let parts = fontColorRGBA.split(separator: " ")
        guard parts.count == 4 else { return "1 1 1 1" }
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(parts[3])"
    }

    var fcpxmlBoxColor: String {
        Self.hexToRGBA(boxColorHex)
    }

    private static func hexToRGBA(_ hex: String) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        return String(format: "%.3f %.3f %.3f 1.000", r, g, b)
    }

    static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    static func hex(from color: Color) -> String {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var burnCLIArgs: [String] {
        // Fallback cũng phải cùng nghĩa với renderer native: effect nhạc không
        // được phủ thêm fade dùng chung lên transition/decoration.
        let fadeIn = hasAppExclusiveEffects ? 0 : (fadeInEnabled ? fadeInMs : 0)
        let fadeOut = hasAppExclusiveEffects ? 0 : (fadeOutEnabled ? fadeOutMs : 0)
        var args = [
            "--font", fontName,
            "--font-size", "\(fontSize)",
            "--text-color", textColorHex,
            "--box-color", boxColorHex,
            "--box-opacity", String(format: "%.2f", boxOpacity),
            "--outline-color", outlineColorHex,
            "--outline-opacity", String(format: "%.2f", outlineOpacity),
            "--outline-width", "\(outlineEnabled ? outlineWidth : 0)",
            "--shadow-color", shadowColorHex,
            "--shadow-opacity", String(format: "%.2f", shadowOpacity),
            "--shadow-blur", "\(shadowEnabled ? shadowBlur : 0)",
            "--shadow-distance", "\(shadowEnabled ? shadowDistance : 0)",
            "--shadow-angle", "\(shadowAngle)",
            "--fade-in", "\(fadeIn)",
            "--fade-out", "\(fadeOut)",
            "--effect-preset", effectPreset.rawValue,
            "--text-transition", textTransition.rawValue,
            "--visual-effect", visualEffect.rawValue,
            "--effect-intensity", String(format: "%.2f", effectIntensity),
            "--effect-speed", String(format: "%.2f", effectSpeed),
            "--effect-direction", effectDirection.rawValue,
            "--effect-density", "\(effectDensity)",
            "--effect-color", effectColorHex,
            "--margin-bottom", "\(marginBottom)",
        ]
        if boxEnabled {
            args.append("--box")
        } else {
            args.append("--no-box")
        }
        return args
    }

    // MARK: - FCPXML (template «Phu de nen den», canvas 1080p)

    /// Neo calibrate: lề đáy 48px (preview @1080) ↔ Position Y = -414 trong FCP.
    private static let fcpxmlRefMarginBottom = 48
    private static let fcpxmlRefPositionY = -414
    private static let fcpxmlRefFontSize = 54
    /// 1 px lề preview = 1 đơn vị Position Y (đồng bộ preview; không phóng 2.75).
    private static let fcpxmlMarginToYScale = 1.0
    /// Font +1pt → nhích Y lên (giữ đáy chữ gần lề).
    private static let fcpxmlFontToYLift = 0.45
    private static let fcpxmlCanvasHeight = 1080.0

    /// Position Y FCP — lề đáy nhỏ (gần mép) → Y âm hơn. Khớp `convert_srt_fcpxml.py`.
    var resolvedFcpxmlPositionY: Int {
        let half = Self.fcpxmlCanvasHeight / 2.0
        let delta = Double(marginBottom - Self.fcpxmlRefMarginBottom) * Self.fcpxmlMarginToYScale
        let fontLift = Self.fcpxmlFontToYLift * Double(fontSize - Self.fcpxmlRefFontSize)
        let y = Double(Self.fcpxmlRefPositionY) + delta + fontLift
        let yMin = -half + 24
        let yMax = -80.0
        let clamped = min(yMax, max(yMin, y))
        return Int(clamped.rounded())
    }

    /// Family + face FCP (từ PostScript name panel font macOS).
    /// VD: PingFangSC-Semibold → ("PingFang SC", "Semibold").
    var fcpxmlFontParts: (family: String, face: String) {
        let n = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return ("PingFang SC", "Regular") }

        // Ưu tiên NSFont — familyName / face chuẩn hệ thống.
        if let font = NSFont(name: n, size: 12) {
            let family = font.familyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let face = (font.fontDescriptor.object(forKey: .face) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let family, !family.isEmpty {
                return (family, (face?.isEmpty == false ? face! : "Regular"))
            }
        }

        // Fallback map PostScript thường gặp.
        let lower = n.lowercased()
        if lower.contains("pingfang") {
            let face = n.split(separator: "-").last.map(String.init) ?? "Regular"
            let region = lower.contains("hk") ? "PingFang HK"
                : lower.contains("tc") ? "PingFang TC" : "PingFang SC"
            return (region, face == n ? "Regular" : face)
        }
        if lower.contains("hiragino") && lower.contains("sans") {
            let face = n.split(separator: "-").last.map(String.init) ?? "W3"
            return ("Hiragino Sans", face == n ? "W3" : face)
        }
        if lower.contains("hiragino") || lower.contains("hirakaku") {
            return ("Hiragino Kaku Gothic Pro", "W3")
        }
        if lower.contains("osaka") { return ("Osaka", "Regular") }
        if lower.contains("arial") && lower.contains("unicode") {
            return ("Arial Unicode MS", "Regular")
        }
        let dashParts = n.split(separator: "-").map(String.init)
        if dashParts.count >= 2 {
            let base = dashParts.dropLast().joined(separator: "-")
            let face = dashParts.last ?? "Regular"
            let family = base
                .replacingOccurrences(
                    of: "([a-z])([A-Z])",
                    with: "$1 $2",
                    options: .regularExpression
                )
                .replacingOccurrences(of: "SC", with: " SC")
            return (family, face)
        }
        return (n, "Regular")
    }

    /// Tên family gửi log / CLI (tương thích cũ).
    var fcpxmlFontName: String { fcpxmlFontParts.family }

    var fcpxmlFontFace: String { fcpxmlFontParts.face }

    /// Toàn bộ style gửi sang convert_srt_fcpxml.py (một nguồn sự thật ↔ preview).
    var fcpxmlCLIArgs: [String] {
        let parts = fcpxmlFontParts
        // Music effects are deliberately app-only. XML receives a clean subtitle title.
        let fadeIn = hasAppExclusiveEffects ? 0 : (fadeInEnabled ? fadeInMs : 0)
        let fadeOut = hasAppExclusiveEffects ? 0 : (fadeOutEnabled ? fadeOutMs : 0)
        return [
            "--fps", fps,
            "--width", "1920",
            "--height", "1080",
            "--font", parts.family,
            "--font-face", parts.face,
            "--font-size", "\(fontSize)",
            "--font-color", fcpxmlFontColor,
            "--outline-color", Self.rgba(outlineColorHex, opacity: outlineEnabled ? outlineOpacity : 0),
            "--outline-width", "\(outlineEnabled ? outlineWidth : 0)",
            "--shadow-color", Self.rgba(shadowColorHex, opacity: shadowEnabled ? shadowOpacity : 0),
            "--shadow-distance", "\(shadowEnabled ? shadowDistance : 0)",
            "--shadow-angle", "\(shadowAngle)",
            // 0 = tắt hộp (khớp preview boxEnabled)
            "--bg-opacity", String(format: "%.2f", boxEnabled ? boxOpacity : 0),
            "--bg-color", fcpxmlBoxColor,
            "--box-width-percent", "\(boxMaxWidthPercent)",
            "--box-corner-radius", "\(boxCornerRadius)",
            "--fade-in-ms", "\(fadeIn)",
            "--fade-out-ms", "\(fadeOut)",
            "--margin-bottom", "\(marginBottom)",
            "--position-y", "\(resolvedFcpxmlPositionY)",
        ]
    }

    private static func rgba(_ hex: String, opacity: Double) -> String {
        let base = hexToRGBA(hex).split(separator: " ")
        guard base.count >= 3 else { return "0 0 0 0" }
        return "\(base[0]) \(base[1]) \(base[2]) \(String(format: "%.3f", max(0, min(1, opacity))))"
    }

    /// Mô tả ngắn cho Nhật ký khi xuất XML.
    var fcpxmlStyleLogLine: String {
        let parts = fcpxmlFontParts
        let box = boxEnabled ? String(format: "bg=%.0f%%", boxOpacity * 100) : "bg=off"
        let fadeIn = hasAppExclusiveEffects ? "app-only" : (fadeInEnabled ? "\(fadeInMs)ms" : "off")
        let fadeOut = hasAppExclusiveEffects ? "app-only" : (fadeOutEnabled ? "\(fadeOutMs)ms" : "off")
        let outline = outlineEnabled ? "\(outlineColorHex) \(outlineWidth)px \(Int(outlineOpacity * 100))%" : "off"
        let shadow = shadowEnabled ? "\(shadowColorHex) \(shadowDistance)px @\(shadowAngle)°" : "off"
        return "XML style: \(parts.family) \(parts.face) \(fontSize)pt · "
            + "lề đáy=\(marginBottom)px → Y=\(resolvedFcpxmlPositionY) · "
            + "chữ=\(textColorHex) · nền=\(boxColorHex) \(box) · "
            + "viền=\(outline) · bóng=\(shadow) · "
            + "rộng=\(boxMaxWidthPercent)% · bo=\(boxCornerRadius) · "
            + "fadeIn=\(fadeIn) fadeOut=\(fadeOut) · fps=\(fps)"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
