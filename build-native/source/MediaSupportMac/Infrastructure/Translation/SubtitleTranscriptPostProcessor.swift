import Foundation

/// Chuẩn hoá cue ngay sau STT. Một cue quá tải được tách thành các cue kề nhau,
/// giữ nguyên span thời gian gốc và cùng rule với preview/SRT/FCPXML.
enum SubtitleTranscriptPostProcessor {
    private enum ScriptFamily {
        case japanese
        case chinese
        case korean
        case thai
        case spaced

        var usesCharacterBreaks: Bool {
            self != .spaced
        }
    }

    /// `sourceLanguage` là hint provider; khi `auto`, suy từ chữ trong cue.
    static func format(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        style: SubtitleWrapStyle,
        fontSize: Int,
        fontName: String = "PingFang SC",
        containerWidth: Double = 1_720,
        maximumSpeechGap: Double? = nil,
        coalescesSpeechChunks: Bool = true,
        wordTimings: [SpeechWordTimestamp] = []
    ) -> [SRTSegment] {
        guard !Task.isCancelled else { return segments }
        if nativeLayoutEnabled {
            return nativeFormat(
                segments,
                sourceLanguage: sourceLanguage,
                style: style,
                fontSize: fontSize,
                fontName: fontName,
                containerWidth: containerWidth,
                maximumSpeechGap: maximumSpeechGap,
                coalescesSpeechChunks: coalescesSpeechChunks,
                wordTimings: wordTimings
            )
        }
        return legacyFormat(
            segments,
            sourceLanguage: sourceLanguage,
            style: style,
            fontSize: fontSize,
            maximumSpeechGap: maximumSpeechGap,
            coalescesSpeechChunks: coalescesSpeechChunks
        )
    }

    /// Cho phép quay lại thuật toán ký tự cũ ngay lập tức nếu một regression hiếm
    /// xuất hiện ở dữ liệu thực. Mặc định bật native engine sau khi golden tests đạt.
    private static var nativeLayoutEnabled: Bool {
        let key = "msm.subtitleLayout.nativeEngine"
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func nativeFormat(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        style: SubtitleWrapStyle,
        fontSize: Int,
        fontName: String,
        containerWidth: Double,
        maximumSpeechGap: Double?,
        coalescesSpeechChunks: Bool,
        wordTimings: [SpeechWordTimestamp]
    ) -> [SRTSegment] {
        let style = style.clamped()
        let perLine = SubtitleWrapStyle.effectiveMaxCharsPerLine(
            base: style.maxCharsPerLine,
            fontSize: fontSize
        )
        let cueBudget = max(perLine, perLine * style.maxLines)
        let normalizedSegments = normalizedSpeechChunks(
            segments,
            sourceLanguage: sourceLanguage,
            cueBudget: cueBudget,
            maximumSpeechGap: maximumSpeechGap,
            coalescesSpeechChunks: coalescesSpeechChunks
        )
        let configuration = SubtitleLayoutConfiguration(
            languageCode: sourceLanguage,
            fontName: fontName,
            fontSize: Double(fontSize),
            containerWidth: containerWidth,
            maxLines: style.maxLines,
            preferredCharactersPerLine: perLine,
            topLineRatio: style.topLineRatio.topOverBottom,
            explicitBreakPolicy: .automatic
        )

        var output: [SRTSegment] = []
        for segment in normalizedSegments {
            guard !Task.isCancelled else { return segments }
            let raw = SubtitleWrapStyle.flattenToOneLine(segment.text)
            guard !raw.isEmpty else { continue }
            let segmentWords = wordTimings.filter {
                $0.startSeconds >= segment.startSeconds - 0.04
                    && $0.endSeconds <= segment.endSeconds + 0.04
            }
            let allowedCueBreakOffsets = SpeechWordTimingProcessor.verifiedCueBreakOffsets(
                in: raw,
                using: segmentWords,
                languageCode: sourceLanguage
            )
            let texts = SubtitleLayoutEngine.layoutPieces(
                raw,
                configuration: configuration,
                allowedCueBreakOffsets: allowedCueBreakOffsets,
                cueBoundaryCosts: SpeechWordTimingProcessor.verifiedCueBoundaryCosts(
                    in: raw, using: segmentWords, languageCode: sourceLanguage
                )
            ).map(\.text)
            output.append(contentsOf: timedPieces(from: segment, texts: texts))
        }
        guard !Task.isCancelled else { return segments }
        return SRTSegmentEditor.reindexed(
            optimizedAdjacentCues(
                output,
                sourceLanguage: sourceLanguage,
                configuration: configuration,
                maximumMergeGap: maximumSpeechGap
            )
        )
    }

    /// Đường lui tương thích. Giữ nguyên trong một chu kỳ phát hành để có thể
    /// vô hiệu hóa engine mới bằng UserDefaults mà không cần thay binary.
    private static func legacyFormat(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        style: SubtitleWrapStyle,
        fontSize: Int,
        maximumSpeechGap: Double?,
        coalescesSpeechChunks: Bool
    ) -> [SRTSegment] {
        let style = style.clamped()
        let perLine = SubtitleWrapStyle.effectiveMaxCharsPerLine(
            base: style.maxCharsPerLine,
            fontSize: fontSize
        )
        let cueBudget = max(perLine, perLine * style.maxLines)

        var output: [SRTSegment] = []
        // Whisper/Groq chia theo nhịp nhận dạng chứ không theo câu. Ví dụ câu Việt
        // `Kính thưa quý vị,` / `mùa báo cáo…` không hề là hai subtitle đẹp.
        // Gom các mảnh kề nhau thành đoạn đọc được trước, rồi mới chia đúng ngân sách
        // 1/2 dòng. Nhờ vậy Preview, SRT và FCPXML nhận cùng một layout sạch.
        let normalizedSegments = normalizedSpeechChunks(
            segments,
            sourceLanguage: sourceLanguage,
            cueBudget: cueBudget,
            maximumSpeechGap: maximumSpeechGap,
            coalescesSpeechChunks: coalescesSpeechChunks
        )
        for segment in normalizedSegments {
            let raw = SubtitleWrapStyle.flattenToOneLine(segment.text)
            guard !raw.isEmpty else { continue }
            let family = family(for: sourceLanguage, text: raw)
            let segmentBudget = naturalCueBudget(
                perLine: perLine,
                maxLines: style.maxLines,
                family: family
            )
            // Không chạy MeCab cho cue vốn đã vừa một khung; tránh chi phí process
            // không cần thiết khi một video có nhiều câu ngắn.
            let mecabBoundaries = family == .japanese && raw.count > segmentBudget
                ? JapaneseMeCabBoundaries.positions(in: raw)
                : []
            let pieces = splitCue(raw, budget: segmentBudget, family: family, mecabBoundaries: mecabBoundaries)
            let styled = pieces.map {
                SubtitleWrapStyle.wrapText(
                    $0,
                    style: style,
                    cjk: family.usesCharacterBreaks,
                    fontSize: fontSize
                )
            }
            output.append(contentsOf: timedPieces(from: segment, texts: styled))
        }
        return SRTSegmentEditor.reindexed(output)
    }

    /// Với Việt/Anh/Nga và các script có khoảng trắng, chế độ 1 dòng là một
    /// câu/cụm tự nhiên. `Chữ/dòng` không còn là dao cắt cứng; chỉ giữ một trần
    /// an toàn rộng để tránh một câu nhận dạng lỗi chạy hết bề ngang màn hình.
    /// Chế độ 2 dòng và các script đặc thù vẫn theo ngân sách chữ/dòng chính xác.
    private static func naturalCueBudget(
        perLine: Int,
        maxLines: Int,
        family: ScriptFamily
    ) -> Int {
        guard maxLines == 1, family == .spaced else {
            return max(perLine, perLine * maxLines)
        }
        return max(56, Int((Double(perLine) * 1.65).rounded()))
    }

    /// Biến chunk kỹ thuật của STT thành đơn vị đọc được. Không gộp qua khoảng
    /// lặng rõ rệt, câu đã kết thúc, hoặc một đoạn quá dài; sau đó `splitCue`
    /// chịu trách nhiệm chia lại theo 1/2 dòng và phân timing theo độ dài text.
    private static func coalesceSpeechChunks(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        cueBudget: Int,
        maximumSpeechGap: Double?
    ) -> [SRTSegment] {
        let maximumCharacters = max(120, cueBudget * 4)
        let maximumDuration = 12.0
        let normalMaximumGap = 0.45
        // Whisper/Groq thường cắt một câu Việt/Latin theo nhịp 2–3 giây và để
        // hở khoảng 0.5–1 giây. Nếu cả hai vế vẫn ngắn, nối chúng để tránh cue
        // rời kiểu "dùng thôn quê nghèo"; gap dài hoặc vế đã đủ dài vẫn tách.
        let shortChunkMaximumGap = 1.15
        let shortChunkLimit = max(32, Int(Double(cueBudget) * 1.25))
        var output: [SRTSegment] = []
        var pending: SRTSegment?

        func flushPending() {
            guard let pending else { return }
            output.append(pending)
        }

        for segment in segments {
            guard !Task.isCancelled else { return segments }
            let text = SubtitleWrapStyle.flattenToOneLine(segment.text)
            guard !text.isEmpty else { continue }
            let normalized = SRTSegmentEditor.withText(segment, text: text)

            guard let previous = pending else {
                pending = normalized
                if endsSentence(text) {
                    flushPending()
                    pending = nil
                }
                continue
            }

            let groupFamily = family(for: sourceLanguage, text: previous.text + text)
            let joined = join(previous.text, text, family: groupFamily)
            let previousLength = previous.text.filter { !$0.isWhitespace }.count
            let currentLength = normalized.text.filter { !$0.isWhitespace }.count
            let bridgesShortSpeechGap = previousLength <= shortChunkLimit && currentLength <= shortChunkLimit
            let allowedGap = maximumSpeechGap.map { max(0, $0) }
                ?? (bridgesShortSpeechGap ? shortChunkMaximumGap : normalMaximumGap)
            let isContinuous = normalized.startSeconds - previous.endSeconds <= allowedGap
            let fitsGroup = joined.filter { !$0.isWhitespace }.count <= maximumCharacters
                && normalized.endSeconds - previous.startSeconds <= maximumDuration
            let previousFinished = endsSentence(previous.text)

            guard isContinuous, fitsGroup, !previousFinished else {
                flushPending()
                pending = normalized
                if endsSentence(text) {
                    flushPending()
                    pending = nil
                }
                continue
            }

            pending = SRTSegment(
                id: previous.id,
                index: previous.index,
                timing: SRTTimecode.makeTiming(start: previous.startSeconds, end: normalized.endSeconds),
                startSeconds: previous.startSeconds,
                endSeconds: normalized.endSeconds,
                text: joined
            )
            if endsSentence(joined) {
                flushPending()
                pending = nil
            }
        }

        flushPending()
        return output
    }

    /// Word timing đã lập ranh giới subtitle từ pause/duration. Đường này chỉ
    /// chuẩn hóa text từng cụm; ghép lại sẽ tái tạo cue dài của segment provider.
    private static func normalizedSpeechChunks(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        cueBudget: Int,
        maximumSpeechGap: Double?,
        coalescesSpeechChunks: Bool
    ) -> [SRTSegment] {
        guard !coalescesSpeechChunks else {
            return coalesceSpeechChunks(
                segments,
                sourceLanguage: sourceLanguage,
                cueBudget: cueBudget,
                maximumSpeechGap: maximumSpeechGap
            )
        }
        return segments.compactMap { segment in
            let text = SubtitleWrapStyle.flattenToOneLine(segment.text)
            guard !text.isEmpty else { return nil }
            return SRTSegmentEditor.withText(segment, text: text)
        }
    }

    private static func endsSentence(_ text: String) -> Bool {
        text.last.map { ".!?…。！？؟۔।॥".contains($0) } ?? false
    }

    private static func join(_ lhs: String, _ rhs: String, family: ScriptFamily) -> String {
        let separator: String
        switch family {
        case .japanese, .chinese, .thai: separator = ""
        case .korean, .spaced: separator = " "
        }
        return SubtitleWrapStyle.flattenToOneLine(lhs + separator + rhs)
    }

    /// Tối ưu các cue đã layout bằng cùng font/safe-area của Preview và export.
    /// Một nhóm chỉ hợp lệ khi layout lại vẫn đúng một cue, duration/CPS an toàn
    /// và không đi qua pause mạnh hoặc dấu hiệu đổi người nói. DP tránh kiểu merge
    /// tuần tự chọn nhầm cặp đầu rồi để lại cue cuối quá ngắn.
    private static func optimizedAdjacentCues(
        _ segments: [SRTSegment],
        sourceLanguage: String,
        configuration: SubtitleLayoutConfiguration,
        maximumMergeGap: Double?
    ) -> [SRTSegment] {
        let ordered = segments.sorted {
            $0.startSeconds == $1.startSeconds ? $0.index < $1.index : $0.startSeconds < $1.startSeconds
        }
        guard ordered.count > 1 else { return ordered }

        let thresholds = adaptiveCueGapThresholds(ordered)
        let count = ordered.count
        var costs = Array(repeating: Double.infinity, count: count + 1)
        var previous = Array(repeating: -1, count: count + 1)
        var chosenText = Array(repeating: "", count: count + 1)
        costs[0] = 0

        for start in 0..<count where costs[start].isFinite {
            guard !Task.isCancelled else { return segments }
            let maximumEnd = min(count - 1, start + 3)
            for end in start...maximumEnd {
                if end > start {
                    let boundaries = start..<end
                    guard boundaries.allSatisfy({ boundary in
                        let gap = max(0, ordered[boundary + 1].startSeconds - ordered[boundary].endSeconds)
                        return gap < thresholds.strong
                            && maximumMergeGap.map { gap <= max(0, $0) + 0.000_5 } != false
                            && !isDialogueBoundary(ordered[boundary].text, ordered[boundary + 1].text)
                    }) else { continue }
                }

                let duration = ordered[end].endSeconds - ordered[start].startSeconds
                guard duration > 0, duration <= 6.001 else { continue }
                let text = joinedCueText(
                    ordered[start...end].map(\.text),
                    languageCode: sourceLanguage
                )
                guard !text.isEmpty else { continue }
                guard let result = SubtitleLayoutEngine.layoutSingleCue(text, configuration: configuration),
                      result.fits else { continue }

                let readableCount = text.filter { !$0.isWhitespace && !$0.isNewline }.count
                let family = SubtitleLayoutEngine.family(languageCode: sourceLanguage, text: text)
                let maximumCPS: Double
                switch family {
                case .japanese, .chinese, .korean: maximumCPS = 12
                case .southEastAsian, .brahmic, .spaced: maximumCPS = 20
                }
                guard Double(readableCount) / duration <= maximumCPS + 0.001 else { continue }

                var groupCost = 24 + pow(duration - 3.8, 2) * 2
                if duration < 1.2 { groupCost += 55 }
                else if duration < 1.7 { groupCost += 18 }

                if end > start {
                    for boundary in start..<end {
                        let lhs = ordered[boundary]
                        let rhs = ordered[boundary + 1]
                        let gap = max(0, rhs.startSeconds - lhs.endSeconds)
                        groupCost += min(18, gap / max(0.05, thresholds.soft) * 8)
                        if endsSentence(lhs.text) {
                            groupCost += gap > 0.12 ? 16 : 7
                        }
                        let lhsDuration = lhs.endSeconds - lhs.startSeconds
                        let rhsDuration = rhs.endSeconds - rhs.startSeconds
                        if endsSentence(lhs.text), lhsDuration > 1.8, rhsDuration > 1.8 {
                            // Hai câu đã đủ thời lượng đọc không nên bị gộp chỉ
                            // vì tổng text tình cờ còn vừa khung.
                            groupCost += 24
                        }
                        if lhsDuration > 2.2, rhsDuration > 2.2 { groupCost += 9 }
                        if gap >= thresholds.soft { groupCost += 14 }
                    }
                }

                let total = costs[start] + groupCost
                if total < costs[end + 1] {
                    costs[end + 1] = total
                    previous[end + 1] = start
                    chosenText[end + 1] = result.text
                }
            }
        }

        guard previous[count] >= 0 else { return ordered }
        var groups: [(start: Int, end: Int, text: String)] = []
        var cursor = count
        while cursor > 0 {
            let start = previous[cursor]
            guard start >= 0 else { return ordered }
            groups.append((start, cursor - 1, chosenText[cursor]))
            cursor = start
        }
        groups.reverse()
        return groups.enumerated().map { offset, group in
            let first = ordered[group.start]
            let last = ordered[group.end]
            return SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: SRTTimecode.makeTiming(start: first.startSeconds, end: last.endSeconds),
                startSeconds: first.startSeconds,
                endSeconds: last.endSeconds,
                text: group.text
            )
        }
    }

    private static func adaptiveCueGapThresholds(
        _ segments: [SRTSegment]
    ) -> (soft: Double, strong: Double) {
        let gaps = zip(segments, segments.dropFirst()).map {
            max(0, $1.startSeconds - $0.endSeconds)
        }.filter { $0 <= 2.5 }.sorted()
        guard !gaps.isEmpty else { return (0.32, 0.65) }
        let position = min(gaps.count - 1, Int((Double(gaps.count - 1) * 0.75).rounded()))
        let local = gaps[position]
        let soft = min(0.48, max(0.26, local + 0.12))
        return (soft, min(0.85, max(0.62, soft + 0.24)))
    }

    private static func joinedCueText(_ texts: [String], languageCode: String) -> String {
        let flattened = texts.map(SubtitleWrapStyle.flattenToOneLine).filter { !$0.isEmpty }
        guard !flattened.isEmpty else { return "" }
        let probe = flattened.joined()
        let family = SubtitleLayoutEngine.family(languageCode: languageCode, text: probe)
        let separator: String
        switch family {
        case .japanese, .chinese, .southEastAsian: separator = ""
        case .korean, .brahmic, .spaced: separator = " "
        }
        return SubtitleWrapStyle.flattenToOneLine(flattened.joined(separator: separator))
    }

    private static func isDialogueBoundary(_ lhs: String, _ rhs: String) -> Bool {
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if right.hasPrefix("-") || right.hasPrefix("–") || right.hasPrefix("—") || right.hasPrefix(">>") {
            return true
        }
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return left.hasSuffix(":") && right.first.map { $0.isUppercase } == true
    }

    private static func family(for language: String, text: String) -> ScriptFamily {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: "-").split(separator: "-").first {
        case "ja", "jp": return .japanese
        case "zh", "yue", "cmn": return .chinese
        case "ko": return .korean
        case "th": return .thai
        default: break
        }
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return .japanese }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return .korean }
        if scalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) { return .thai }
        if scalars.contains(where: { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }) { return .chinese }
        return .spaced
    }

    private static func splitCue(
        _ text: String,
        budget: Int,
        family: ScriptFamily,
        mecabBoundaries: Set<Int>
    ) -> [String] {
        let chars = Array(text)
        guard chars.count > budget else { return [text] }
        var result: [String] = []
        var start = 0
        while start < chars.count {
            let remaining = chars.count - start
            guard remaining > budget else {
                result.append(String(chars[start...]).trimmingCharacters(in: .whitespaces))
                break
            }
            let end = start + budget
            let cut = bestCut(
                chars,
                start: start,
                preferredEnd: end,
                family: family,
                mecabBoundaries: mecabBoundaries
            )
            let safeCut = max(start + 1, min(chars.count - 1, cut))
            let piece = String(chars[start..<safeCut]).trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { break }
            result.append(piece)
            start = safeCut
            while start < chars.count, chars[start].isWhitespace { start += 1 }
        }
        return result.isEmpty ? [text] : result
    }

    private static func bestCut(
        _ chars: [Character],
        start: Int,
        preferredEnd: Int,
        family: ScriptFamily,
        mecabBoundaries: Set<Int>
    ) -> Int {
        // Dấu câu tốt nhất khi vế trước đủ dài. Không được chẻ cue ở một lời
        // dẫn ngắn kiểu `Kính thưa quý vị,` chỉ vì có dấu phẩy ở đầu câu.
        let minimumPunctuationPiece = max(6, Int(Double(preferredEnd - start) * 0.45))
        if let punct = stride(from: preferredEnd, through: start + minimumPunctuationPiece, by: -1).first(where: {
            "。！？…、，,.!?;；:：".contains(chars[$0 - 1])
        }) {
            return avoidingDanglingTail(chars, start: start, cut: punct, family: family)
        }
        if family == .spaced {
            // Latin/Cyrillic/Arabic: chỉ cắt tại ranh giới từ; một từ dài giữ nguyên.
            if let space = stride(from: preferredEnd, through: start + 1, by: -1).first(where: {
                chars[$0 - 1].isWhitespace
            }) { return avoidingDanglingTail(chars, start: start, cut: space, family: family) }
            if let nextSpace = ((preferredEnd + 1)..<chars.count).first(where: { chars[$0].isWhitespace }) {
                return nextSpace
            }
            return chars.count
        }
        // Nhật: MeCab cung cấp ranh giới từ/cụm; dấu câu ở trên vẫn thắng tuyệt đối.
        // Thiếu MeCab/UniDic thì bỏ qua và dùng Kinsoku phía dưới, không làm job thất bại.
        if family == .japanese,
           let mecab = mecabBoundaries
            .filter({ $0 > start && $0 <= preferredEnd && isKinsokuSafe(chars, cut: $0) })
            .max() {
            return mecab
        }
        // JP/ZH/KO/TH: tách theo ký tự nhưng không để đầu dòng là dấu/trợ từ kinsoku phổ biến.
        var cut = preferredEnd
        while cut > start + 1, !isKinsokuSafe(chars, cut: cut) {
            cut -= 1
        }
        return cut
    }

    /// Nếu phần còn lại chỉ là vài chữ không kết câu, lùi điểm cắt về một ranh giới
    /// từ trước đó. Mục tiêu là tránh cue kiểu `trường` thay vì cố lấp đầy tuyệt đối.
    private static func avoidingDanglingTail(
        _ chars: [Character],
        start: Int,
        cut: Int,
        family: ScriptFamily
    ) -> Int {
        guard family == .spaced, cut > start, cut < chars.count else { return cut }
        let trailing = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
        let trailingCount = trailing.filter { !$0.isWhitespace }.count
        let endsSentence = trailing.last.map { ".!?…。！？".contains($0) } ?? false
        guard trailingCount > 0, trailingCount < 16, !endsSentence else { return cut }

        for earlierCut in stride(from: cut - 1, through: start + 1, by: -1) where chars[earlierCut - 1].isWhitespace {
            let candidateTail = String(chars[earlierCut...]).trimmingCharacters(in: .whitespaces)
            if candidateTail.filter({ !$0.isWhitespace }).count >= 16 {
                return earlierCut
            }
        }
        return cut
    }

    private static func isKinsokuSafe(_ chars: [Character], cut: Int) -> Bool {
        guard cut > 0, cut < chars.count else { return cut > 0 }
        if "はがをにのへとでやも、。！？…」』）】".contains(chars[cut]) { return false }
        if "「『（【".contains(chars[cut - 1]) { return false }
        return true
    }

    private static func timedPieces(from segment: SRTSegment, texts: [String]) -> [SRTSegment] {
        guard texts.count > 1 else {
            return [SRTSegmentEditor.withText(segment, text: texts.first ?? segment.text)]
        }
        let weights = texts.map { max(1, $0.filter { !$0.isWhitespace }.count) }
        let totalWeight = max(1, weights.reduce(0, +))
        let duration = max(0.001, segment.endSeconds - segment.startSeconds)
        var cursor = segment.startSeconds
        return texts.enumerated().map { offset, text in
            let end: Double
            if offset == texts.count - 1 {
                end = segment.endSeconds
            } else {
                end = cursor + duration * Double(weights[offset]) / Double(totalWeight)
            }
            defer { cursor = end }
            return SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: SRTTimecode.makeTiming(start: cursor, end: end),
                startSeconds: cursor,
                endSeconds: end,
                text: text
            )
        }
    }
}

/// MeCab/UniDic chỉ là nâng cấp ranh giới tiếng Nhật. App vẫn có Kinsoku fallback
/// để chạy được trên máy chưa cài dictionary, không làm hỏng Groq/Offline.
private enum JapaneseMeCabBoundaries {
    static func positions(in text: String) -> Set<Int> {
        guard !text.isEmpty else { return [] }
        let dictionaries = [
            "/opt/homebrew/lib/mecab/dic/unidic",
            "/usr/local/lib/mecab/dic/unidic",
            "/opt/homebrew/lib/mecab/dic/ipadic",
            "/usr/local/lib/mecab/dic/ipadic",
        ]
        let dictionary = dictionaries.first { FileManager.default.fileExists(atPath: $0) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = dictionary.map { ["mecab", "-r", "/dev/null", "-d", $0] } ?? ["mecab"]
        let input = Pipe()
        let output = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            input.fileHandleForWriting.write(Data((text + "\n").utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
            var position = 0
            var boundaries: Set<Int> = []
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                guard line != "EOS", let surface = line.split(separator: "\t", maxSplits: 1).first,
                      !surface.isEmpty else { continue }
                position += surface.count
                if position < text.count { boundaries.insert(position) }
            }
            return boundaries
        } catch {
            return []
        }
    }
}
