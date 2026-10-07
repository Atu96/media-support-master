import CoreText
import Foundation

enum SubtitleLayoutLanguageFamily: Equatable, Sendable {
    case spaced
    case japanese
    case chinese
    case korean
    case southEastAsian
    case brahmic
}

enum SubtitleExplicitBreakPolicy: Equatable, Sendable {
    /// Enter của người dùng là dữ liệu có chủ ý. Engine chỉ đo và báo lỗi, không viết lại.
    case preserve
    /// Dữ liệu từ STT/provider được chuẩn hóa rồi engine tự chọn lại vị trí ngắt.
    case automatic
}

enum SubtitleLayoutIssueCode: String, Equatable, Sendable {
    case lineOverflow
    case tooManyLines
    case emergencyClusterBreak
}

struct SubtitleLayoutIssue: Equatable, Sendable {
    let code: SubtitleLayoutIssueCode
    let line: Int?
}

struct SubtitleLayoutConfiguration: Equatable, Sendable {
    var languageCode: String
    var fontName: String
    var fontSize: Double
    /// Bề rộng nội dung text thật, đã trừ padding hộp sub, tại canvas tham chiếu.
    var containerWidth: Double
    var maxLines: Int
    /// Giá trị legacy/UI cũ. Chỉ tạo độ rộng đọc thoải mái; không còn là dao cắt cứng.
    var preferredCharactersPerLine: Int
    /// Dòng trên / dòng dưới. 0.5 = dạng bottom-heavy 1:2; 1 = cân bằng.
    var topLineRatio: Double
    var explicitBreakPolicy: SubtitleExplicitBreakPolicy

    init(
        languageCode: String = "auto",
        fontName: String = "PingFang SC",
        fontSize: Double = 54,
        containerWidth: Double = 1_720,
        maxLines: Int = 2,
        preferredCharactersPerLine: Int = 33,
        topLineRatio: Double = 0.5,
        explicitBreakPolicy: SubtitleExplicitBreakPolicy = .automatic
    ) {
        self.languageCode = languageCode
        self.fontName = fontName
        self.fontSize = fontSize
        self.containerWidth = containerWidth
        self.maxLines = maxLines
        self.preferredCharactersPerLine = preferredCharactersPerLine
        self.topLineRatio = topLineRatio
        self.explicitBreakPolicy = explicitBreakPolicy
    }

    func clamped() -> SubtitleLayoutConfiguration {
        var copy = self
        copy.fontSize = min(240, max(10, fontSize))
        copy.containerWidth = max(copy.fontSize * 2, containerWidth)
        copy.maxLines = min(2, max(1, maxLines))
        copy.preferredCharactersPerLine = min(80, max(12, preferredCharactersPerLine))
        copy.topLineRatio = min(1, max(0.35, topLineRatio))
        return copy
    }
}

struct SubtitleLayoutResult: Equatable, Sendable {
    let text: String
    let lines: [String]
    let lineWidths: [Double]
    let issues: [SubtitleLayoutIssue]

    var fits: Bool { issues.allSatisfy { $0.code != .lineOverflow && $0.code != .tooManyLines } }
}

/// Engine layout subtitle native. Core Text là nguồn đo glyph/kerning và line opportunity;
/// tailoring ngôn ngữ chỉ chọn điểm semantic trong các ranh giới không phá grapheme.
enum SubtitleLayoutEngine {
    /// Cache sống đúng một lần layout. Cùng substring thường được DP, line-break
    /// và cue scoring hỏi lại nhiều lần; không cần cache toàn app hoặc khóa luồng.
    private final class TextMeasurer {
        private let font: CTFont
        private var widths: [String: Double] = [:]
        private let contextText: String?
        private let languageCode: String
        private var analyzed = false
        private var analysis: SubtitleLinguisticBoundaryContext?
        let cueBoundaryCosts: [Int: Double]

        init(fontName: String, fontSize: Double, contextText: String? = nil,
             languageCode: String = "auto", cueBoundaryCosts: [Int: Double] = [:]) {
            font = CTFontCreateWithName(fontName as CFString, max(1, fontSize), nil)
            self.contextText = contextText.flatMap {
                SubtitleLinguisticBoundaryContext.isJapanese(languageCode: languageCode, text: $0) ? nil : $0
            }
            self.languageCode = languageCode
            self.cueBoundaryCosts = cueBoundaryCosts
        }

        var context: SubtitleLinguisticBoundaryContext? {
            if !analyzed {
                analyzed = true
                if let contextText {
                    analysis = SubtitleLinguisticBoundaryContext(text: contextText, languageCode: languageCode)
                }
            }
            return analysis
        }

        func boundaryCost(at offset: Int, cue: Bool = false) -> Double {
            guard let context else { return 0 } // Nhật giữ nguyên điểm số cũ.
            return context.cost(at: offset) * (cue ? 0.55 : 1)
                + (cue ? (cueBoundaryCosts[offset] ?? 0) : 0)
        }

        func width(of text: String) -> Double {
            guard !text.isEmpty else { return 0 }
            if let cached = widths[text] { return cached }
            let attributed = NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            let value = CTLineGetTypographicBounds(line, nil, nil, nil)
            if widths.count < 4_096 { widths[text] = value }
            return value
        }
    }

    private enum BreakStrength: Int, Hashable {
        case emergency = 0
        case word = 1
        case softPunctuation = 2
        case strongPunctuation = 3
        case sentence = 4
    }

    private struct BreakCandidate: Hashable {
        let offset: Int // Character offset, không phải UTF-16 offset.
        let strength: BreakStrength
        let isLexicalBoundary: Bool
    }

    private static let sentencePunctuation: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    private static let strongPunctuation: Set<Character> = [";", "；", ":", "："]
    private static let softPunctuation: Set<Character> = [",", "，", "、", "—", "–", "・"]
    private static let prohibitedLineStart: Set<Character> = [
        ")", "]", "}", "〉", "》", "」", "』", "】", "〕", "〗", "〙", "〛",
        ",", ".", ":", ";", "!", "?", "，", "。", "、", "：", "；", "！", "？", "…",
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ",
        "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ", "ー",
    ]
    private static let prohibitedLineEnd: Set<Character> = [
        "(", "[", "{", "〈", "《", "「", "『", "【", "〔", "〖", "〘", "〚",
    ]

    private static let headOrphans: Set<String> = [
        "ạ", "ư", "nhé", "nhỉ", "đấy", "đâu",
    ]
    private static let tailOrphans: Set<String> = [
        "và", "hoặc", "hay", "nhưng", "mà", "nên", "vì", "của", "cho", "với", "từ", "đến", "là",
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "but", "with", "from",
    ]
    private static let vietnameseForwardBinders: Set<String> = [
        "các", "những", "mọi", "mỗi", "một", "chiếc", "con", "người", "sự", "việc", "điều",
        "không", "chưa", "chẳng", "đang", "đã", "sẽ", "vẫn", "rất", "quá",
    ]
    private static let englishForwardBinders: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
        "am", "is", "are", "was", "were", "be", "been", "being", "do", "does", "did", "have", "has", "had",
        "can", "could", "may", "might", "must", "shall", "should", "will", "would", "not",
    ]
    private static let preferredLineStarts: Set<String> = [
        "và", "hoặc", "hay", "nhưng", "mà", "nên", "vì", "nếu", "khi", "trong", "ngoài", "với", "từ", "đến", "cho", "để",
        "and", "or", "but", "because", "if", "when", "while", "although", "with", "from", "to", "for", "in", "on", "at", "by", "of",
    ]

    /// Tiếng Việt dùng khoảng trắng giữa âm tiết, nên whitespace không luôn là
    /// một ranh giới ngữ nghĩa tốt như tiếng Anh. Danh sách này chỉ chứa các
    /// liên kết rất ổn định; phần còn lại được xử lý bằng điểm orphan/toàn chuỗi.
    private static let vietnameseBondedPairs: Set<String> = [
        "an toàn", "ấn tượng", "bao gồm", "bắt đầu", "bảo vệ", "bộ phận",
        "bầu trời", "chiến đấu", "chiến dịch", "chiến thuật", "công nghệ", "cơ động",
        "đối thủ", "đồng thời", "hiện đại", "hệ thống", "khả năng", "không quân",
        "hải quân", "hủy diệt", "máy bay", "mặt đất", "mục tiêu", "nhiệm vụ",
        "né tránh", "phát triển", "phi công", "quốc phòng", "sân bay", "sức mạnh",
        "tác chiến", "tàu sân", "tiêm kích", "tiên tiến", "toàn bộ", "trận chiến",
        "trở thành", "tự hào", "vũ khí", "vượt trội", "gia đình", "thời gian",
        "thông tin", "vấn đề", "kết quả", "công việc", "cuộc sống", "chúng ta",
        "hôm nay", "ngày mai", "thế giới", "bây giờ", "tại sao", "như thế",
        "có thể", "cần phải", "được biết", "cho rằng",
    ]
    private static let russianOrphans: Set<String> = [
        "а", "без", "в", "во", "для", "до", "за", "и", "из", "или", "к", "ко",
        "на", "над", "но", "о", "об", "от", "по", "под", "при", "с", "со", "у",
    ]
    private static let measurementUnits: Set<String> = [
        "%", "km", "km/h", "kg", "g", "m", "cm", "mm", "hz", "khz", "mhz", "ghz",
        "mph", "mach", "mb", "gb", "tb", "triệu", "tỷ", "đồng", "usd", "eur",
    ]

    static func family(languageCode: String, text: String) -> SubtitleLayoutLanguageFamily {
        let normalized = resolvedLanguageCode(languageCode, text: text)
        switch normalized {
        case "ja": return .japanese
        case "zh", "yue", "cmn": return .chinese
        case "ko": return .korean
        case "th", "lo", "km": return .southEastAsian
        case "hi", "bn", "pa", "gu", "or", "ta", "te", "kn", "ml", "si", "my", "jv": return .brahmic
        default: break
        }

        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return .japanese }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return .korean }
        if scalars.contains(where: {
            (0x0E00...0x0E7F).contains($0.value)
                || (0x0E80...0x0EFF).contains($0.value)
                || (0x1780...0x17FF).contains($0.value)
        }) { return .southEastAsian }
        if scalars.contains(where: { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }) {
            return .chinese
        }
        if scalars.contains(where: {
            (0x0900...0x0DFF).contains($0.value)
                || (0x1000...0x109F).contains($0.value)
                || (0xA980...0xA9DF).contains($0.value)
        }) { return .brahmic }
        return .spaced
    }

    /// Layout một cue hoặc chia thành nhiều cue text nếu nội dung không thể vừa số dòng.
    /// Hàm pure/deterministic: chạy lần hai trên output không làm đổi text.
    static func layoutPieces(
        _ raw: String,
        configuration: SubtitleLayoutConfiguration,
        allowedCueBreakOffsets: Set<Int>? = nil,
        cueBoundaryCosts: [Int: Double] = [:]
    ) -> [SubtitleLayoutResult] {
        let config = configuration.clamped()
        let normalized = normalize(raw, preservingBreaks: config.explicitBreakPolicy == .preserve)
        guard !normalized.isEmpty else { return [] }

        if config.explicitBreakPolicy == .preserve, normalized.contains("\n") {
            return [manualResult(normalized, configuration: config)]
        }

        let text = flatten(normalized)
        guard !text.isEmpty else { return [] }
        let family = family(languageCode: config.languageCode, text: text)
        let measurer = TextMeasurer(fontName: config.fontName, fontSize: config.fontSize,
            contextText: family == .japanese ? nil : text, languageCode: config.languageCode,
            cueBoundaryCosts: cueBoundaryCosts)
        let lineWidth = automaticLineWidth(configuration: config, family: family)

        // Nhật giữ nguyên đường Kinsoku/MeCab đã được chốt. Những họ chữ còn lại
        // dùng cùng optimizer toàn chuỗi cho cả một và hai dòng; hai dòng chỉ
        // thêm một quyết định layout bên trong mỗi cue.
        if family != .japanese,
           layoutAsSingleCue(
                text,
                configuration: config,
                family: family,
                lineWidth: lineWidth,
                measurer: measurer
           ) == nil,
           let optimized = optimizedLayoutPieces(
                text,
                configuration: config,
                family: family,
                lineWidth: lineWidth,
                allowedCueBreakOffsets: allowedCueBreakOffsets,
                measurer: measurer
           ) {
            return optimized
        }

        var remaining = text
        var remainingStart = 0
        var output: [SubtitleLayoutResult] = []
        var safety = 0
        while !remaining.isEmpty, safety < 1_000, !Task.isCancelled {
            safety += 1
            if let laidOut = layoutAsSingleCue(
                remaining,
                configuration: config,
                family: family,
                lineWidth: lineWidth,
                measurer: measurer,
                textStart: remainingStart
            ) {
                output.append(laidOut)
                break
            }

            let cut = bestCueCut(
                remaining,
                configuration: config,
                family: family,
                lineWidth: lineWidth,
                measurer: measurer,
                textStart: remainingStart,
                allowedCueBreakOffsets: family == .japanese ? nil : allowedCueBreakOffsets
            )
            guard cut > 0, cut < remaining.count else {
                output.append(emergencyResult(
                    remaining,
                    configuration: config,
                    lineWidth: lineWidth,
                    measurer: measurer
                ))
                break
            }
            let characters = Array(remaining)
            let head = String(characters[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(characters[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty, !tail.isEmpty else {
                output.append(emergencyResult(
                    remaining,
                    configuration: config,
                    lineWidth: lineWidth,
                    measurer: measurer
                ))
                break
            }
            output.append(
                layoutAsSingleCue(
                    head,
                    configuration: config,
                    family: family,
                    lineWidth: lineWidth,
                    measurer: measurer,
                    textStart: remainingStart
                ) ?? emergencyResult(
                    head,
                    configuration: config,
                    lineWidth: lineWidth,
                    measurer: measurer
                )
            )
            remainingStart += cut + characters[cut...].prefix(while: { $0.isWhitespace }).count
            remaining = tail
        }
        return output
    }

    static func measuredWidth(
        of text: String,
        fontName: String,
        fontSize: Double
    ) -> Double {
        TextMeasurer(fontName: fontName, fontSize: fontSize).width(of: text)
    }

    // MARK: - Manual layout

    private static func manualResult(
        _ text: String,
        configuration: SubtitleLayoutConfiguration
    ) -> SubtitleLayoutResult {
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map {
            measuredWidth(of: $0, fontName: configuration.fontName, fontSize: configuration.fontSize)
        }
        var issues: [SubtitleLayoutIssue] = []
        if lines.count > configuration.maxLines {
            issues.append(SubtitleLayoutIssue(code: .tooManyLines, line: nil))
        }
        for (index, width) in widths.enumerated() where width > configuration.containerWidth + 0.5 {
            issues.append(SubtitleLayoutIssue(code: .lineOverflow, line: index))
        }
        return SubtitleLayoutResult(text: lines.joined(separator: "\n"), lines: lines, lineWidths: widths, issues: issues)
    }

    // MARK: - Automatic layout

    private static func layoutAsSingleCue(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily,
        lineWidth: Double,
        measurer: TextMeasurer,
        textStart: Int = 0,
        allowsWeakBreaks: Bool = false
    ) -> SubtitleLayoutResult? {
        let fullWidth = measurer.width(of: text)
        if fullWidth <= lineWidth + 0.5 {
            return SubtitleLayoutResult(text: text, lines: [text], lineWidths: [fullWidth], issues: [])
        }
        guard configuration.maxLines >= 2,
              let split = bestLineBreak(
                text,
                configuration: configuration,
                family: family,
                lineWidth: lineWidth,
                measurer: measurer,
                textStart: textStart,
                allowsWeakBreaks: allowsWeakBreaks
              ) else {
            return nil
        }
        let chars = Array(text)
        let left = String(chars[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(chars[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        let widths = [left, right].map { measurer.width(of: $0) }
        guard widths.allSatisfy({ $0 <= lineWidth + 0.5 }) else { return nil }
        return SubtitleLayoutResult(
            text: left + "\n" + right,
            lines: [left, right],
            lineWidths: widths,
            issues: []
        )
    }

    private static func bestLineBreak(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily,
        lineWidth: Double,
        measurer: TextMeasurer,
        textStart: Int = 0,
        allowsWeakBreaks: Bool = false
    ) -> Int? {
        let chars = Array(text)
        let candidates = breakCandidates(text, family: family, languageCode: configuration.languageCode,
            width: lineWidth, configuration: configuration, measurer: measurer, textStart: textStart)
        let targetFraction = configuration.topLineRatio / (1 + configuration.topLineRatio)
        var best: (score: Double, offset: Int)?

        for candidate in candidates where candidate.offset > 0 && candidate.offset < chars.count {
            guard !Task.isCancelled else { return nil }
            guard isLegalBreak(chars, at: candidate.offset) else { continue }
            let left = String(chars[..<candidate.offset]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(chars[candidate.offset...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { continue }
            let leftWidth = measurer.width(of: left)
            let rightWidth = measurer.width(of: right)
            guard leftWidth <= lineWidth + 0.5, rightWidth <= lineWidth + 0.5 else { continue }
            let linguisticCost = measurer.boundaryCost(at: textStart + candidate.offset)
            guard allowsWeakBreaks || linguisticCost < 85 else { continue }

            let total = max(1, leftWidth + rightWidth)
            var score = abs((leftWidth / total) - targetFraction) * 120
            score -= Double(candidate.strength.rawValue) * 14
            score += lexicalBoundaryAdjustment(candidate, family: family)
            score += linguisticCost
            score += orphanPenalty(
                left: left,
                right: right,
                languageCode: configuration.languageCode,
                family: family
            )
            if min(leftWidth, rightWidth) < lineWidth * 0.18 { score += 42 }
            if best == nil || score < best!.score { best = (score, candidate.offset) }
        }
        return best?.offset
    }

    private static func bestCueCut(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily,
        lineWidth: Double,
        measurer: TextMeasurer,
        textStart: Int = 0,
        allowedCueBreakOffsets: Set<Int>? = nil
    ) -> Int {
        let chars = Array(text)
        let candidates = breakCandidates(text, family: family, languageCode: configuration.languageCode,
            width: lineWidth * Double(configuration.maxLines), configuration: configuration,
            measurer: measurer, textStart: textStart)
        var best: (score: Double, offset: Int)?

        for candidate in candidates where candidate.offset > 0 && candidate.offset < chars.count {
            guard !Task.isCancelled else { return 0 }
            guard allowedCueBreakOffsets?.contains(textStart + candidate.offset) != false else { continue }
            guard isLegalBreak(chars, at: candidate.offset) else { continue }
            let head = String(chars[..<candidate.offset]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty,
                  layoutAsSingleCue(
                    head,
                    configuration: configuration,
                    family: family,
                    lineWidth: lineWidth,
                    measurer: measurer,
                    textStart: textStart
                  ) != nil else { continue }
            let fill = Double(candidate.offset) / Double(max(1, chars.count))
            var score = (1 - fill) * 100
            score -= Double(candidate.strength.rawValue) * 18
            score += lexicalBoundaryAdjustment(candidate, family: family)
            score += measurer.boundaryCost(at: textStart + candidate.offset, cue: true)
            let tail = String(chars[candidate.offset...]).trimmingCharacters(in: .whitespacesAndNewlines)
            score += orphanPenalty(
                left: head,
                right: tail,
                languageCode: configuration.languageCode,
                family: family
            )
            if best == nil || score < best!.score { best = (score, candidate.offset) }
        }
        if let best { return best.offset }
        if let allowedCueBreakOffsets {
            return allowedCueBreakOffsets.filter { $0 > textStart && $0 < textStart + chars.count }
                .min().map { $0 - textStart } ?? chars.count
        }
        return emergencyClusterCut(text, configuration: configuration, width: lineWidth * Double(configuration.maxLines))
    }

    private static func emergencyResult(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        lineWidth: Double,
        measurer: TextMeasurer
    ) -> SubtitleLayoutResult {
        if configuration.maxLines >= 2 {
            let cut = emergencyClusterCut(text, configuration: configuration, width: lineWidth)
            let chars = Array(text)
            if cut > 0, cut < chars.count {
                let left = String(chars[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(chars[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let widths = [left, right].map { measurer.width(of: $0) }
                return SubtitleLayoutResult(
                    text: left + "\n" + right,
                    lines: [left, right],
                    lineWidths: widths,
                    issues: [SubtitleLayoutIssue(code: .emergencyClusterBreak, line: nil)]
                        + widths.enumerated().compactMap { index, value in
                            value > lineWidth + 0.5 ? SubtitleLayoutIssue(code: .lineOverflow, line: index) : nil
                        }
                )
            }
        }
        let width = measurer.width(of: text)
        let issues = width > lineWidth + 0.5
            ? [SubtitleLayoutIssue(code: .lineOverflow, line: 0)]
            : []
        return SubtitleLayoutResult(text: text, lines: [text], lineWidths: [width], issues: issues)
    }

    /// Quy hoạch động trên toàn bộ break opportunities. Mỗi cạnh là một cue vừa
    /// đúng chiều rộng Core Text; điểm số ưu tiên ít cue, dấu câu, độ đầy vừa phải
    /// và ranh giới ngữ nghĩa. Vì đoạn STT đã được chặn kích thước ở post-processor,
    /// số candidate nhỏ và không nằm trên đường playback/skim.
    private static func optimizedLayoutPieces(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily,
        lineWidth: Double,
        allowedCueBreakOffsets: Set<Int>?,
        measurer: TextMeasurer
    ) -> [SubtitleLayoutResult]? {
        let chars = Array(text)
        let generated = breakCandidates(
            text,
            family: family,
            languageCode: configuration.languageCode,
            width: lineWidth * Double(configuration.maxLines),
            configuration: configuration,
            measurer: measurer
        )
        var strengthAt: [Int: BreakStrength] = [:]
        var candidateAt: [Int: BreakCandidate] = [:]
        for candidate in generated {
            strengthAt[candidate.offset] = candidate.strength
            candidateAt[candidate.offset] = candidate
        }
        for offset in allowedCueBreakOffsets ?? [] where offset > 0 && offset < chars.count {
            if candidateAt[offset] == nil {
                candidateAt[offset] = BreakCandidate(
                    offset: offset,
                    strength: .word,
                    isLexicalBoundary: true
                )
                strengthAt[offset] = .word
            }
        }
        let offsets = ([0] + Array(candidateAt.keys) + [chars.count])
            .filter { $0 == 0 || $0 == chars.count || isLegalBreak(chars, at: $0) }
            .filter { offset in
                offset == 0 || offset == chars.count || allowedCueBreakOffsets?.contains(offset) != false
            }
            .sorted()
        guard offsets.count >= 3 else { return nil }

        var best = Array(repeating: Double.infinity, count: offsets.count)
        var previous = Array(repeating: -1, count: offsets.count)
        best[0] = 0

        for endIndex in 1..<offsets.count {
            guard !Task.isCancelled else { return nil }
            let end = offsets[endIndex]
            for startIndex in stride(from: endIndex - 1, through: 0, by: -1) {
                guard best[startIndex].isFinite else { continue }
                let start = offsets[startIndex]
                let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                let pieceStart = start + chars[start..<end].prefix(while: { $0.isWhitespace }).count
                guard !piece.isEmpty else { continue }
                guard let layout = layoutAsSingleCue(
                    piece,
                    configuration: configuration,
                    family: family,
                    lineWidth: lineWidth,
                    measurer: measurer,
                    textStart: pieceStart
                ) else {
                    // Một cạnh có thể bị loại vì cụm nghĩa, dù vẫn vừa khung.
                    // Khi đó cạnh dài hơn có thể có một điểm ngắt tốt khác.
                    if configuration.maxLines == 2,
                       layoutAsSingleCue(piece, configuration: configuration, family: family,
                           lineWidth: lineWidth, measurer: measurer, textStart: pieceStart,
                           allowsWeakBreaks: true) != nil { continue }
                    break
                }

                let usedWidth = layout.lineWidths.reduce(0, +)
                let capacity = lineWidth * Double(max(1, layout.lines.count))
                let fill = min(1, usedWidth / max(1, capacity))
                var cost = 24 + pow(1 - fill, 2) * 22
                if end < chars.count {
                    let left = piece
                    let right = String(chars[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !isProtectedSemanticBreak(
                        left: left,
                        right: right,
                        languageCode: configuration.languageCode
                    ) else { continue }
                    cost += orphanPenalty(
                        left: left,
                        right: right,
                        languageCode: configuration.languageCode,
                        family: family
                    )
                    cost -= Double(strengthAt[end]?.rawValue ?? 0) * 7
                    cost += measurer.boundaryCost(at: end, cue: true)
                    if let candidate = candidateAt[end] {
                        cost += lexicalBoundaryAdjustment(candidate, family: family)
                    }
                } else if fill < 0.34 {
                    // Đuôi cuối quá ngắn là lỗi dễ thấy nhất ở mode một dòng.
                    cost += (0.34 - fill) * 150
                }

                let candidate = best[startIndex] + cost
                if candidate < best[endIndex] {
                    best[endIndex] = candidate
                    previous[endIndex] = startIndex
                }
            }
        }

        guard previous[offsets.count - 1] >= 0 else { return nil }
        var ranges: [(Int, Int)] = []
        var cursor = offsets.count - 1
        while cursor > 0 {
            let startIndex = previous[cursor]
            guard startIndex >= 0 else { return nil }
            ranges.append((offsets[startIndex], offsets[cursor]))
            cursor = startIndex
        }
        ranges.reverse()
        guard ranges.count > 1 else { return nil }
        return ranges.map { start, end in
            let piece = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            let pieceStart = start + chars[start..<end].prefix(while: { $0.isWhitespace }).count
            return layoutAsSingleCue(
                piece,
                configuration: configuration,
                family: family,
                lineWidth: lineWidth,
                measurer: measurer,
                textStart: pieceStart
            ) ?? emergencyResult(
                piece,
                configuration: configuration,
                lineWidth: lineWidth,
                measurer: measurer
            )
        }
    }

    // MARK: - Candidate generation

    private static func breakCandidates(
        _ text: String,
        family: SubtitleLayoutLanguageFamily,
        languageCode: String,
        width: Double,
        configuration: SubtitleLayoutConfiguration,
        measurer: TextMeasurer? = nil,
        textStart: Int = 0
    ) -> [BreakCandidate] {
        let chars = Array(text)
        var strengths: [Int: (strength: BreakStrength, lexical: Bool)] = [:]

        func add(_ offset: Int, _ strength: BreakStrength, lexical: Bool = false) {
            guard offset > 0, offset < chars.count else { return }
            if let current = strengths[offset], current.strength.rawValue > strength.rawValue { return }
            if let current = strengths[offset], current.strength == strength {
                strengths[offset] = (strength, current.lexical || lexical)
            } else {
                strengths[offset] = (strength, lexical)
            }
        }

        for index in chars.indices {
            let ch = chars[index]
            if ch.isWhitespace { add(index + 1, .word, lexical: true) }
            if sentencePunctuation.contains(ch), !isNumericSeparator(chars, at: index) { add(index + 1, .sentence) }
            if strongPunctuation.contains(ch), !isNumericSeparator(chars, at: index) { add(index + 1, .strongPunctuation) }
            if softPunctuation.contains(ch), !isNumericSeparator(chars, at: index) { add(index + 1, .softPunctuation) }
        }

        if let context = measurer?.context {
            for offset in context.lexicalOffsets where offset > textStart && offset < textStart + chars.count {
                add(offset - textStart, .word, lexical: true)
            }
        } else {
            for offset in tokenizerBoundaries(text, languageCode: languageCode) {
                add(offset, .word, lexical: true)
            }
        }

        if family == .japanese || family == .chinese {
            for offset in 1..<chars.count { add(offset, .word) }
        }

        if let suggested = coreTextSuggestedBreak(text, configuration: configuration, width: width) {
            add(suggested, .word)
        }

        return strengths.map {
            BreakCandidate(
                offset: $0.key,
                strength: $0.value.strength,
                isLexicalBoundary: $0.value.lexical
            )
        }
            .sorted { $0.offset < $1.offset }
    }

    private static func tokenizerBoundaries(_ text: String, languageCode: String) -> Set<Int> {
        var boundaries: Set<Int> = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            let offset = text[..<range.upperBound].count
            if offset > 0, offset < text.count { boundaries.insert(offset) }
        }
        return boundaries
    }

    private static func coreTextSuggestedBreak(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        width: Double
    ) -> Int? {
        let font = CTFontCreateWithName(configuration.fontName as CFString, configuration.fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let utf16Offset = CTTypesetterSuggestLineBreak(typesetter, 0, width)
        guard utf16Offset > 0, utf16Offset < text.utf16.count,
              let index = stringIndex(in: text, utf16Offset: utf16Offset) else { return nil }
        return text[..<index].count
    }

    private static func emergencyClusterCut(
        _ text: String,
        configuration: SubtitleLayoutConfiguration,
        width: Double
    ) -> Int {
        let font = CTFontCreateWithName(configuration.fontName as CFString, configuration.fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let utf16Offset = CTTypesetterSuggestClusterBreak(typesetter, 0, width)
        guard utf16Offset > 0, let index = stringIndex(in: text, utf16Offset: utf16Offset) else {
            return min(max(1, text.count / 2), max(1, text.count - 1))
        }
        return min(max(1, text[..<index].count), max(1, text.count - 1))
    }

    private static func stringIndex(in text: String, utf16Offset: Int) -> String.Index? {
        guard utf16Offset >= 0, utf16Offset <= text.utf16.count,
              let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset, limitedBy: text.utf16.endIndex) else {
            return nil
        }
        return String.Index(utf16Index, within: text)
    }

    // MARK: - Rules and measurement

    /// Merge chỉ cần kiểm tra một cue có vừa hay không. Không chạy DP chia cue
    /// cho nhóm sẽ bị loại; dùng chính phép đo/điểm ngắt của layoutPieces.
    static func layoutSingleCue(
        _ raw: String,
        configuration: SubtitleLayoutConfiguration
    ) -> SubtitleLayoutResult? {
        let config = configuration.clamped()
        let normalized = normalize(raw, preservingBreaks: config.explicitBreakPolicy == .preserve)
        guard !normalized.isEmpty, !Task.isCancelled else { return nil }
        if config.explicitBreakPolicy == .preserve, normalized.contains("\n") {
            let result = manualResult(normalized, configuration: config)
            return result.fits ? result : nil
        }
        let text = flatten(normalized)
        let family = family(languageCode: config.languageCode, text: text)
        return layoutAsSingleCue(
            text, configuration: config, family: family,
            lineWidth: automaticLineWidth(configuration: config, family: family),
            measurer: TextMeasurer(fontName: config.fontName, fontSize: config.fontSize,
                contextText: family == .japanese ? nil : text, languageCode: config.languageCode)
        )
    }

    private static func automaticLineWidth(
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily
    ) -> Double {
        guard configuration.maxLines == 1 else {
            return preferredLineWidth(configuration: configuration, family: family)
        }
        let characters = max(configuration.preferredCharactersPerLine, recommendedOneLineCharacters(family))
        return min(configuration.containerWidth,
                   averageGlyphWidth(configuration: configuration, family: family) * Double(characters))
    }

    private static func preferredLineWidth(
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily
    ) -> Double {
        let average = averageGlyphWidth(configuration: configuration, family: family)
        return min(configuration.containerWidth, average * Double(configuration.preferredCharactersPerLine))
    }

    private static func averageGlyphWidth(
        configuration: SubtitleLayoutConfiguration,
        family: SubtitleLayoutLanguageFamily
    ) -> Double {
        let sample: String
        switch family {
        case .japanese: sample = "字幕日本語読みやすい表示"
        case .chinese: sample = "字幕中文清晰易读画面"
        case .korean: sample = "자막한국어읽기쉬운화면"
        case .southEastAsian: sample = "ภาษาไทยคำบรรยาย"
        case .brahmic: sample = "उपशीर्षकपाठनमूना"
        case .spaced: sample = "Subtitle sample 0123456789"
        }
        return max(
            configuration.fontSize * 0.38,
            measuredWidth(of: sample, fontName: configuration.fontName, fontSize: configuration.fontSize)
                / Double(max(1, sample.count))
        )
    }

    private static func recommendedOneLineCharacters(_ family: SubtitleLayoutLanguageFamily) -> Int {
        switch family {
        case .japanese, .chinese: return 20
        case .korean: return 24
        case .southEastAsian, .brahmic: return 32
        case .spaced: return 42
        }
    }

    private static func isLegalBreak(_ chars: [Character], at offset: Int) -> Bool {
        guard offset > 0, offset < chars.count else { return false }
        if prohibitedLineEnd.contains(chars[offset - 1]) { return false }
        if prohibitedLineStart.contains(chars[offset]) { return false }
        if isNumericSeparator(chars, at: offset - 1) { return false }
        if isInsideModelToken(chars, offset: offset) {
            // `F-18`, `Su-35`, `B–52`: Core Text có thể đề xuất cluster break
            // quanh dấu nối khi sát mép, nhưng subtitle không được chẻ model.
            return false
        }
        return true
    }

    private static func isModelJoiner(_ character: Character) -> Bool {
        character == "-" || character == "‑" || character == "–"
    }

    private static func isInsideModelToken(_ chars: [Character], offset: Int) -> Bool {
        if isModelJoiner(chars[offset]), offset > 0, offset + 1 < chars.count {
            let leftIsAlphaNumeric = chars[offset - 1].isLetter || chars[offset - 1].isNumber
            let rightIsAlphaNumeric = chars[offset + 1].isLetter || chars[offset + 1].isNumber
            return leftIsAlphaNumeric && rightIsAlphaNumeric
        }
        if isModelJoiner(chars[offset - 1]), offset >= 2 {
            let leftIsAlphaNumeric = chars[offset - 2].isLetter || chars[offset - 2].isNumber
            let rightIsAlphaNumeric = chars[offset].isLetter || chars[offset].isNumber
            return leftIsAlphaNumeric && rightIsAlphaNumeric
        }
        return false
    }

    private static func isNumericSeparator(_ chars: [Character], at index: Int) -> Bool {
        guard chars.indices.contains(index), chars[index] == "." || chars[index] == ",",
              index > 0, index + 1 < chars.count else { return false }
        return chars[index - 1].wholeNumberValue != nil && chars[index + 1].wholeNumberValue != nil
    }

    private static func orphanPenalty(
        left: String,
        right: String,
        languageCode: String,
        family: SubtitleLayoutLanguageFamily
    ) -> Double {
        let clean = CharacterSet.punctuationCharacters.union(.symbols)
        let last = left.split(whereSeparator: { $0.isWhitespace }).last.map(String.init)?
            .trimmingCharacters(in: clean).lowercased() ?? ""
        let first = right.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?
            .trimmingCharacters(in: clean).lowercased() ?? ""
        var penalty = 0.0
        if tailOrphans.contains(last) { penalty += 44 }
        if headOrphans.contains(first) { penalty += 44 }
        let rightWords = right.split(whereSeparator: { $0.isWhitespace })
        if rightWords.count == 1, right.count <= 10 { penalty += 46 }
        if rightWords.count <= 2, right.count <= 18 { penalty += 24 }

        let language = resolvedLanguageCode(languageCode, text: left + " " + right)
        if language == "vi", vietnameseBondedPairs.contains(last + " " + first) {
            penalty += 180
        }
        if language == "vi", vietnameseForwardBinders.contains(last) {
            penalty += 96
        }
        if language == "en", englishForwardBinders.contains(last) {
            penalty += 96
        }
        if preferredLineStarts.contains(first) {
            // Với subtitle hai dòng, trước liên từ/giới từ thường là một điểm
            // ngắt tự nhiên hơn sau chính từ chức năng đó.
            penalty -= 22
        }
        if language == "ru", russianOrphans.contains(last) || russianOrphans.contains(first) {
            penalty += 70
        }
        if isNumericToken(last), measurementUnits.contains(first) { penalty += 180 }
        if looksLikeModelOrEntityBridge(leftToken: last, rightToken: first) { penalty += 120 }

        // Với CJK/Hàn, dấu câu và luật cấm đầu/cuối đã là tín hiệu chính; không
        // áp hình phạt đuôi theo số “từ” Latin vì sẽ làm lệch Kinsoku.
        if family == .chinese || family == .korean || family == .southEastAsian || family == .brahmic {
            penalty *= 0.75
        }
        return penalty
    }

    private static func lexicalBoundaryAdjustment(
        _ candidate: BreakCandidate,
        family: SubtitleLayoutLanguageFamily
    ) -> Double {
        guard family != .japanese else { return 0 }
        switch family {
        case .chinese:
            return candidate.isLexicalBoundary ? -20 : (candidate.strength == .word ? 8 : 0)
        case .korean:
            // Hàn có thể được Core Text bẻ trong một eojeol. Chỉ dùng đường đó
            // khi không còn ranh giới từ/dấu câu vừa khung.
            return candidate.isLexicalBoundary ? -14 : (candidate.strength == .word ? 72 : 0)
        case .southEastAsian, .brahmic:
            return candidate.isLexicalBoundary ? -12 : (candidate.strength == .word ? 18 : 0)
        case .spaced:
            return candidate.isLexicalBoundary ? -4 : 0
        case .japanese:
            return 0
        }
    }

    private static func isProtectedSemanticBreak(
        left: String,
        right: String,
        languageCode: String
    ) -> Bool {
        let clean = CharacterSet.punctuationCharacters.union(.symbols)
        let last = left.split(whereSeparator: { $0.isWhitespace }).last.map(String.init)?
            .trimmingCharacters(in: clean).lowercased() ?? ""
        let first = right.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?
            .trimmingCharacters(in: clean).lowercased() ?? ""
        let language = resolvedLanguageCode(languageCode, text: left + " " + right)
        if language == "vi", vietnameseBondedPairs.contains(last + " " + first) { return true }
        if isNumericToken(last), measurementUnits.contains(first) { return true }
        if looksLikeModelOrEntityBridge(leftToken: last, rightToken: first) { return true }
        return false
    }

    private static func isNumericToken(_ token: String) -> Bool {
        token.rangeOfCharacter(from: .decimalDigits) != nil
            && token.rangeOfCharacter(from: .letters) == nil
    }

    private static func looksLikeModelOrEntityBridge(leftToken: String, rightToken: String) -> Bool {
        guard !leftToken.isEmpty, !rightToken.isEmpty else { return false }
        let leftHasModelMarker = leftToken.contains("-") || leftToken.rangeOfCharacter(from: .decimalDigits) != nil
        let rightStartsUppercase = rightToken.first.map { String($0) == String($0).uppercased() && String($0) != String($0).lowercased() } ?? false
        return leftHasModelMarker && rightStartsUppercase
    }

    private static func resolvedLanguageCode(_ languageCode: String, text: String) -> String {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init) ?? "auto"
        if normalized != "auto", !normalized.isEmpty { return normalized }
        if looksVietnamese(text) { return "vi" }
        // Script detection in `family` covers the languages that need tailoring.
        // Spaced languages share word/punctuation opportunities, so core layout does
        // not need a heavyweight language recognizer on the real-time path.
        return "auto"
    }

    /// Không chạy language recognizer nặng trên đường layout. Các chữ cái dưới
    /// đây là dấu hiệu chính tả đặc trưng đủ mạnh của tiếng Việt; chỉ cần một chữ
    /// nền ă/â/đ/ê/ô/ơ/ư hoặc một nguyên âm mang dấu tiếng Việt là kích hoạt rule.
    private static func looksVietnamese(_ text: String) -> Bool {
        let normalized = text.lowercased().precomposedStringWithCanonicalMapping
        let markers = "ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
        return normalized.contains { markers.contains($0) }
    }

    private static func normalize(_ raw: String, preservingBreaks: Bool) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
        if preservingBreaks {
            text = text.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = flatten(text)
        }
        return text
    }

    private static func flatten(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
