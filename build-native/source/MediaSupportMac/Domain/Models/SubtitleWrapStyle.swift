import Foundation

/// Tỉ lệ độ dài dòng trên : dòng dưới.
enum SubtitleTopLineRatio: String, CaseIterable, Identifiable, Codable, Sendable {
    case equal
    case half
    /// Legacy UserDefaults — map về equal, không hiện trên UI.
    case twoThirds

    var id: String { rawValue }

    /// Chỉ 1:1 và 1:2 trên panel.
    static var uiCases: [SubtitleTopLineRatio] { [.equal, .half] }

    var label: String {
        switch self {
        case .equal: "1 : 1"
        case .half: "1 : 2"
        case .twoThirds: "1 : 1"
        }
    }

    /// top / bottom (1:2 → 0.5).
    var topOverBottom: Double {
        switch self {
        case .equal, .twoThirds: return 1.0
        case .half: return 0.5
        }
    }

    /// Phần ký tự dòng trên trong tổng 2 dòng (0…1).
    /// 1:1 → 0.5 · 1:2 → ≈0.333
    var idealSplitFraction: Double {
        let r = topOverBottom
        return r / (1.0 + r)
    }

    /// Chuẩn hóa legacy.
    var normalized: SubtitleTopLineRatio {
        switch self {
        case .twoThirds: return .equal
        default: return self
        }
    }
}

/// Ngôn ngữ text mẫu đang xem trên preview.
enum SubtitleSamplePreviewKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case latin
    case ideographic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latin: "Latin"
        case .ideographic: "Tượng hình"
        }
    }
}

/// Rule ngắt dòng + text mẫu (tự điền / chỉnh tay).
struct SubtitleWrapStyle: Codable, Equatable, Sendable {
    var maxLines: Int = 2
    var maxCharsPerLine: Int = 33
    var topLineRatio: SubtitleTopLineRatio = .half
    var sampleLatin: String = ""
    var sampleJapanese: String = ""
    var samplePreviewKind: SubtitleSamplePreviewKind = .latin

    static let storageKey = "msm.subtitleWrapStyle"
    /// Một lần: đẩy mặc định mới (33 chữ) nếu user chưa chỉnh tay khỏi default cũ.
    private static let defaultsBumpKey = "msm.subtitleWrapStyle.defaultsBump.v33"

    /// Mặc định: 2 dòng · 33 chữ · 1:2 (dòng trên ngắn hơn).
    static var appDefault: SubtitleWrapStyle {
        SubtitleWrapStyle(
            maxLines: 2,
            maxCharsPerLine: 33,
            topLineRatio: .half
        )
    }

    var maxBlockChars: Int {
        max(maxCharsPerLine, maxCharsPerLine * max(1, min(3, maxLines)))
    }

    var isAppDefault: Bool {
        let d = Self.appDefault
        let c = clamped()
        return c.maxLines == d.maxLines
            && c.maxCharsPerLine == d.maxCharsPerLine
            && c.topLineRatio == d.topLineRatio
    }

    static func load() -> SubtitleWrapStyle {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey),
              var style = try? JSONDecoder().decode(SubtitleWrapStyle.self, from: data) else {
            defaults.set(true, forKey: defaultsBumpKey)
            return .appDefault
        }
        style = style.clamped()
        // Default cũ = 42 → 33 (một lần). Giữ nếu user đã đổi khác 42.
        if !defaults.bool(forKey: defaultsBumpKey) {
            defaults.set(true, forKey: defaultsBumpKey)
            if style.maxCharsPerLine == 42 {
                style.maxCharsPerLine = 33
                style.save()
            }
        }
        return style
    }

    func save() {
        let value = clamped()
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func clamped() -> SubtitleWrapStyle {
        var copy = self
        // UI/chế độ chép lời chỉ hỗ trợ 1 hoặc 2 dòng. Không để preset cũ 3 dòng
        // làm pipeline sau STT và preview/export bất nhất.
        copy.maxLines = min(2, max(1, maxLines))
        copy.maxCharsPerLine = min(80, max(12, maxCharsPerLine))
        copy.topLineRatio = topLineRatio.normalized
        return copy
    }

    func withMaxLines(_ lines: Int) -> SubtitleWrapStyle {
        var copy = clamped()
        copy.maxLines = min(3, max(1, lines))
        return copy
    }

    mutating func autoFillSamples() {
        let s = clamped()
        sampleLatin = Self.generateLatinSample(for: s)
        sampleJapanese = Self.generateJapaneseSample(for: s)
    }

    func withAutoFilledSamples() -> SubtitleWrapStyle {
        var copy = clamped()
        copy.autoFillSamples()
        return copy
    }

    // MARK: - Preview

    func previewLatin() -> String {
        let raw = sampleLatin.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = raw.isEmpty ? Self.generateLatinSample(for: self) : raw
        return Self.wrapText(source, style: self, cjk: false)
    }

    func previewJapanese() -> String {
        let raw = sampleJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = raw.isEmpty ? Self.generateJapaneseSample(for: self) : raw
        return Self.wrapText(source, style: self, cjk: true)
    }

    func previewActiveSample() -> String {
        switch samplePreviewKind {
        case .latin: return previewLatin()
        case .ideographic: return previewJapanese()
        }
    }

    var previewActiveBadge: String {
        samplePreviewKind.label
    }

    // MARK: - Generators

    private static let latinWords = [
        "Welcome", "back", "everyone", "today", "we", "shape", "clean", "subtitle",
        "lines", "so", "every", "phrase", "stays", "easy", "to", "read", "on",
        "screen", "while", "keeping", "natural", "word", "breaks", "and", "timing",
        "balanced", "for", "viewers", "watching", "your", "video", "content", "online",
    ]

    private static let japaneseChunks = [
        "こんにちは", "今日は", "字幕の", "改行と", "フォントを", "整えて",
        "見やすい", "表示を", "確認します", "二行の", "バランスも", "大切です",
        "読みやすさ", "を第一に", "調整して", "ください", "サンプル", "テキスト",
    ]

    static func generateLatinSample(for style: SubtitleWrapStyle) -> String {
        let s = style.clamped()
        let target = s.maxCharsPerLine * max(s.maxLines, 1) + max(8, s.maxCharsPerLine / 3)
        var parts: [String] = []
        var len = 0
        var i = 0
        while len < target {
            let w = latinWords[i % latinWords.count]
            parts.append(w)
            len = parts.joined(separator: " ").count
            i += 1
            if i > 200 { break }
        }
        return parts.joined(separator: " ")
    }

    static func generateJapaneseSample(for style: SubtitleWrapStyle) -> String {
        let s = style.clamped()
        let target = s.maxCharsPerLine * max(s.maxLines, 1) + max(4, s.maxCharsPerLine / 4)
        var out = ""
        var i = 0
        while out.count < target {
            out += japaneseChunks[i % japaneseChunks.count]
            i += 1
            if i > 200 { break }
        }
        return out
    }

    static func looksIdeographic(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    // MARK: - Wrap

    /// Cỡ chữ chuẩn mà `maxCharsPerLine` được calibrate (mặc định app = 54pt).
    static let referenceFontSize: Int = 54

    /// Dấu câu ưu tiên ngắt (sau ký tự này).
    private static let strongPunct: Set<Character> = [
        "。", "！", "？", "…", ".", "!", "?", "；", ";",
    ]
    private static let softPunct: Set<Character> = [
        "、", "，", ",", "：", ":", "—", "–", "・",
    ]

    /// Chuẩn hóa 1 hàng (gộp \n → space), đồng thời sửa lỗi STT tách một từ Latin
    /// thành các ký tự đơn lẻ, ví dụ `a b o a r d` → `aboard`.
    ///
    /// Cố ý chỉ gộp chuỗi từ 4 ký tự, có ít nhất một chữ thường. Vì vậy các viết tắt
    /// ngắn/toàn hoa như `AI`, `USA`, `BBC` vẫn được giữ nguyên.
    static func flattenToOneLine(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizeSpacedLatinWords(normalized)
    }

    private static func normalizeSpacedLatinWords(_ text: String) -> String {
        let pattern = #"(?<![A-Za-z])(?:[A-Za-z]\s+){3,}[A-Za-z](?![A-Za-z])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }

        let originalRange = NSRange(text.startIndex..., in: text)
        let matches = expression.matches(in: text, range: originalRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let fragment = String(result[range])
            // Không đụng chuỗi chữ in hoa cách nhau: đó thường là acronym có chủ ý.
            guard fragment.rangeOfCharacter(from: .lowercaseLetters) != nil else { continue }
            let merged = fragment.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            result.replaceSubrange(range, with: merged)
        }
        return result
    }

    /// Đếm ký tự “chữ/dòng” (CJK = số ký tự; Latin bỏ space vẫn đếm như hiển thị length).
    static func displayCharCount(_ text: String) -> Int {
        flattenToOneLine(text).count
    }

    /// Ngân sách chữ/dòng **thật** khi đã tính cỡ chữ (font lớn → ít chữ hơn trên màn).
    ///
    /// `maxCharsPerLine` user = mức tại `referenceFontSize` (54pt).
    /// - 54pt · 33 → 33
    /// - 72pt · 33 → ~25
    /// - 40pt · 33 → ~36 (nới nhẹ, tối đa ~1.2× base)
    static func effectiveMaxCharsPerLine(base: Int, fontSize: Int) -> Int {
        let base = min(80, max(12, base))
        let fs = max(18.0, Double(fontSize))
        let scale = Double(referenceFontSize) / fs
        let raw = Double(base) * scale
        let adjusted: Double
        if scale < 1 {
            // Font lớn hơn ref → siết chặt (đẩy xuống hàng sớm hơn)
            adjusted = raw
        } else {
            // Font nhỏ hơn → nới nhẹ, không vượt quá 1.2× base
            adjusted = min(raw, Double(base) * 1.2)
        }
        return min(80, max(12, Int(adjusted.rounded())))
    }

    /// Đổi một ngân sách đang hiển thị ở cỡ chữ hiện tại về base lưu nội bộ 54pt.
    /// Dùng phép tìm rời rạc thay vì chia trực tiếp vì `effective…` có clamp/cap.
    static func baseMaxCharsPerLine(displayed value: Int, fontSize: Int) -> Int {
        let target = min(80, max(12, value))
        return (12...80).min {
            let lhs = abs(effectiveMaxCharsPerLine(base: $0, fontSize: fontSize) - target)
            let rhs = abs(effectiveMaxCharsPerLine(base: $1, fontSize: fontSize) - target)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        } ?? target
    }

    /// Gợi ý chữ/dòng đang **hiển thị** ở cỡ chữ hiện tại. Ví dụ tiếng Việt
    /// 54pt = 33, 72pt ≈25; do đó nút Tự động không còn luôn trả về 33.
    /// Giá trị này được đổi về base 54pt trước khi lưu để pipeline không scale hai lần.
    static func recommendedMaxCharsPerLine(languageCode: String, fontSize: Int) -> Int {
        let language = languageCode.lowercased().split(separator: "-").first.map(String.init) ?? "auto"
        let base: Int
        switch language {
        case "ja", "zh", "yue", "cmn": base = 16
        case "ko": base = 18
        case "th": base = 24
        default: base = 33
        }
        return effectiveMaxCharsPerLine(base: base, fontSize: fontSize)
    }

    /// - `forceTwoLines == false` (auto): ≤ **effective** chữ/dòng (đã tính font) → 1 hàng,
    ///   **trừ** khi có dấu câu chia 2 vế đủ dài
    /// - `fontSize`: cỡ burn/preview — font lớn = ngân sách dòng hẹp hơn
    /// - `forceTwoLines == true`: luôn cố 2 hàng, **dấu câu thắng tuyệt đối**
    /// - `maxLines == 1`: ép 1 hàng
    static func wrapText(
        _ raw: String,
        style: SubtitleWrapStyle,
        forceTwoLines: Bool = false,
        cjk: Bool? = nil,
        fontSize: Int = SubtitleWrapStyle.referenceFontSize
    ) -> String {
        let style = style.clamped()
        let text = flattenToOneLine(raw)
        guard !text.isEmpty else { return text }

        if style.maxLines <= 1, !forceTwoLines {
            return text
        }

        // Chữ/dòng user × scale theo cỡ chữ → ngân sách thật trên màn.
        let maxLine = effectiveMaxCharsPerLine(base: style.maxCharsPerLine, fontSize: fontSize)
        let isCJK = cjk ?? looksIdeographic(text)

        // Dưới max (đã tính font): vẫn ưu tiên ngắt sau 、。 nếu hai vế đủ dài.
        if !forceTwoLines, text.count <= maxLine {
            if let punct = bestPunctSplit(text, maxLine: maxLine, style: style, cjk: isCJK, underMaxOnly: true) {
                return punct
            }
            return text
        }
        if forceTwoLines, text.count < 4 {
            return text
        }

        return wrapTwoLines(text, style: style, maxLine: maxLine, cjk: isCJK, forceSplit: forceTwoLines)
    }

    /// Dấu `.`/`,` nằm giữa hai chữ số là một phần của số (100.000, 12,5),
    /// không phải điểm để xuống hàng. Tách tại đây làm preview và SRT rất khó đọc.
    private static func isNumericGroupSeparator(_ chars: [Character], at index: Int) -> Bool {
        guard chars.indices.contains(index),
              chars[index] == "." || chars[index] == ",",
              index > chars.startIndex,
              index < chars.index(before: chars.endIndex) else { return false }
        return chars[index - 1].wholeNumberValue != nil && chars[index + 1].wholeNumberValue != nil
    }

    private static func isAfterPunct(_ chars: [Character], at index: Int) -> Bool {
        guard chars.indices.contains(index), !isNumericGroupSeparator(chars, at: index) else { return false }
        let ch = chars[index]
        return strongPunct.contains(ch) || softPunct.contains(ch)
    }

    private static func isSoftPunct(_ chars: [Character], at index: Int) -> Bool {
        guard chars.indices.contains(index), !isNumericGroupSeparator(chars, at: index) else { return false }
        return softPunct.contains(chars[index])
    }

    /// Ngắt sau dấu câu tốt nhất; `underMaxOnly` = chỉ khi cả hai vế ≤ maxLine và ≥ minSide.
    private static func bestPunctSplit(
        _ text: String,
        maxLine: Int,
        style: SubtitleWrapStyle,
        cjk: Bool,
        underMaxOnly: Bool
    ) -> String? {
        let chars = Array(text)
        let n = chars.count
        guard n >= 8 else { return nil }
        let softMax = maxLine + 10
        let minSide = cjk ? 6 : 4
        let fraction = style.topLineRatio.normalized.idealSplitFraction
        let ideal = max(1, min(n - 1, Int((Double(n) * fraction).rounded())))
        var best: (score: Double, index: Int)?

        for i in 1..<n {
            guard isAfterPunct(chars, at: i - 1) else { continue }
            let leftLen = i
            let rightLen = n - i
            guard leftLen >= minSide, rightLen >= minSide else { continue }
            let lim = softMax
            if underMaxOnly {
                guard leftLen <= maxLine, rightLen <= maxLine else { continue }
            } else {
                guard leftLen <= lim, rightLen <= lim else { continue }
            }
            if cjk {
                let next = chars[i]
                if "はがをにのへとでやも、。！？…」』）".contains(next) { continue }
            }
            var score = abs(Double(i) - Double(ideal)) * 0.12
            if isSoftPunct(chars, at: i - 1) { score += 0.4 }
            // Không phạt mạnh top dài hơn khi đã là punct — punct thắng tỷ lệ 1:2
            if style.topLineRatio.normalized == .half, leftLen > rightLen {
                score += Double(leftLen - rightLen) * 0.08
            }
            if best == nil || score < best!.score {
                best = (score, i)
            }
        }
        guard let b = best else { return nil }
        let left = String(chars.prefix(b.index)).trimmingCharacters(in: .whitespaces)
        let right = String(chars.suffix(n - b.index)).trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return left + "\n" + right
    }

    /// Chia 2 dòng: **dấu câu trước**, tỷ lệ / ước lượng sau. Không cướp punct vì 1:2.
    /// `maxLine` = effective (đã scale theo font).
    private static func wrapTwoLines(
        _ text: String,
        style: SubtitleWrapStyle,
        maxLine: Int,
        cjk: Bool,
        forceSplit: Bool
    ) -> String {
        let chars = Array(text)
        let n = chars.count
        if n < 2 { return text }

        // Phase 0: chỉ dấu câu (、。) — thắng tuyệt đối, kể cả top dài hơn bottom.
        if let punct = bestPunctSplit(text, maxLine: maxLine, style: style, cjk: cjk, underMaxOnly: false) {
            return punct
        }

        let fraction = style.topLineRatio.normalized.idealSplitFraction
        var ideal = Int((Double(n) * fraction).rounded())
        ideal = max(1, min(n - 1, ideal))

        let softMax = maxLine + 10
        let minTop: Int
        let maxTop: Int
        if forceSplit, n <= softMax * 2 {
            minTop = 1
            maxTop = n - 1
        } else {
            minTop = max(1, n - softMax)
            maxTop = min(softMax, n - 1)
            guard minTop <= maxTop else { return text }
        }
        ideal = min(max(ideal, minTop), maxTop)

        var candidates: [(score: Double, index: Int)] = []

        for i in minTop...maxTop {
            let leftLen = i
            let rightLen = n - i
            guard leftLen >= 1, rightLen >= 1 else { continue }
            guard leftLen <= maxLine, rightLen <= maxLine else { continue }

            let prev = chars[i - 1]
            let next = i < n ? chars[i] : nil

            if !cjk {
                let afterSpace = prev == " "
                let beforeSpace = (next == " ")
                if !afterSpace && !beforeSpace {
                    continue
                }
            } else {
                if let next, "はがをにのへとでやも、。！？…」』）".contains(next) {
                    continue
                }
                if "「『（【".contains(prev) {
                    continue
                }
            }

            var score: Double
            if prev == " " {
                score = 800 + abs(Double(i) - Double(ideal)) * 0.5
            } else {
                score = 1000 + abs(Double(i) - Double(ideal))
            }

            if style.topLineRatio.normalized == .half, leftLen > rightLen {
                score += Double(leftLen - rightLen) * 2.5
            } else if style.topLineRatio.normalized != .half {
                score += abs(Double(leftLen) - Double(rightLen)) * 0.12
            }

            if rightLen <= 2 { score += 18 }
            if leftLen <= 2 { score += 12 }

            candidates.append((score, i))
        }

        if candidates.isEmpty {
            for i in minTop...maxTop {
                let prev = chars[i - 1]
                let next = i < n ? chars[i] : nil
                // Fallback cũng không được chém giữa một từ Latin. Đây là nhánh xảy ra
                // khi cue dài hơn ngân sách 2 dòng sau khi người dùng đổi Chữ / dòng.
                if !cjk, prev != " ", next != " " {
                    continue
                }
                if cjk {
                    if let next, "はがをにのへとでやも、。！？".contains(next) { continue }
                    if "「『（".contains(prev) { continue }
                }
                let score = abs(Double(i) - Double(ideal))
                candidates.append((score, i))
            }
        }

        if candidates.isEmpty {
            // CJK có thể ngắt theo ký tự; Latin không được cắt giữa từ. Một từ đơn lẻ
            // vượt ngân sách thì để nguyên hơn là tạo subtitle lỗi đọc được.
            if !cjk { return text }
            let cut = min(maxTop, max(minTop, ideal))
            let left = String(chars.prefix(cut)).trimmingCharacters(in: .whitespaces)
            let right = String(chars.suffix(n - cut)).trimmingCharacters(in: .whitespaces)
            if left.isEmpty { return right }
            if right.isEmpty { return left }
            return left + "\n" + right
        }

        candidates.sort { $0.score < $1.score }
        let best = candidates[0].index
        var left = String(chars.prefix(best)).trimmingCharacters(in: .whitespaces)
        var right = String(chars.suffix(n - best)).trimmingCharacters(in: .whitespaces)

        if !cjk {
            right = right.trimmingCharacters(in: .whitespaces)
            left = left.trimmingCharacters(in: .whitespaces)
        }

        // 1:2 chỉ khi KHÔNG có punct (phase 0 đã return). Không cướp ngắt giữa cụm vô lý.
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + "\n" + right
    }

    private static func fillWordsToMax(_ text: String, maxChars: Int) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return fillLatinLine(words: &words, maxChars: maxChars)
    }

    private static func fillLatinLine(words: inout [String], maxChars: Int) -> String {
        var line = ""
        while let w = words.first {
            let candidate = line.isEmpty ? w : line + " " + w
            if candidate.count > maxChars {
                if line.isEmpty {
                    line = w
                    words.removeFirst()
                }
                break
            }
            line = candidate
            words.removeFirst()
        }
        return line
    }
}
