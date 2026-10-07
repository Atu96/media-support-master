import Foundation

/// Envelope năng lượng đã rút gọn từ lần decode waveform có sẵn. Domain chỉ
/// đọc độ tin cậy khoảng lặng; không giữ PCM và không phụ thuộc AVFoundation.
struct SpeechBoundaryAudioEvidence: Equatable, Sendable {
    let silenceScores: [Float]
    let duration: Double

    func confidence(from startSeconds: Double, to endSeconds: Double) -> Double {
        guard !silenceScores.isEmpty,
              duration.isFinite, duration > 0,
              startSeconds.isFinite, endSeconds.isFinite,
              endSeconds - startSeconds >= 0.20 else { return 0 }
        let count = silenceScores.count
        let lower = min(count - 1, max(0, Int(floor(startSeconds / duration * Double(count)))))
        let upper = min(count - 1, max(lower, Int(ceil(endSeconds / duration * Double(count))) - 1))
        guard upper >= lower else { return 0 }
        let values = silenceScores[lower...upper].map(Double.init).sorted()
        guard !values.isEmpty else { return 0 }
        // Median không để một click hoặc một bin nhạc nền đơn lẻ quyết định cue.
        return min(1, max(0, values[values.count / 2]))
    }
}

/// Chuyển timestamp từng từ của provider thành cue timing mà không phụ thuộc
/// schema Groq. Mọi hàm đều thuần; dữ liệu thiếu/lệch trả về đường fallback.
enum SpeechWordTimingProcessor {
    private struct PauseThresholds {
        let soft: Double
        let strong: Double
    }

    /// Diagnostic rollback không cần thay binary. Mặc định bật; chỉ explicit
    /// `false` mới quay về planner pause cố định của build trước.
    private static var adaptivePauseEnabled: Bool {
        let key = "msm.subtitleTiming.adaptivePause"
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func hasMatchingTranscript(
        words: [SpeechWordTimestamp],
        transcript: String
    ) -> Bool {
        let wordKey = alignmentKey(words.map(\.text).joined())
        let transcriptKey = alignmentKey(transcript)
        guard !wordKey.isEmpty, !transcriptKey.isEmpty else { return false }
        return wordKey == transcriptKey
    }

    /// Lập cụm lời dành cho subtitle từ timestamp từng từ. Segment provider chỉ
    /// là dữ liệu nhận dạng; cue cuối phải ưu tiên pause/câu, nhịp 4–5 giây và
    /// không vượt trần 6 giây khi lời nói chạy liên tục.
    static func makeSegments(
        from rawWords: [SpeechWordTimestamp],
        languageCode: String,
        audioEvidence: SpeechBoundaryAudioEvidence? = nil,
        pauseThreshold: Double = 0.45,
        preferredDuration: Double = 4.5,
        maximumDuration: Double = 6.0,
        minimumClauseDuration: Double = 2.2
    ) -> [SRTSegment] {
        let words = normalized(rawWords)
        guard !words.isEmpty else { return [] }

        let preferredDuration = max(1.5, preferredDuration)
        let maximumDuration = max(preferredDuration, maximumDuration)
        let minimumClauseDuration = max(0.8, min(minimumClauseDuration, preferredDuration))
        guard adaptivePauseEnabled else {
            return legacySegments(
                words,
                languageCode: languageCode,
                pauseThreshold: pauseThreshold,
                preferredDuration: preferredDuration,
                maximumDuration: maximumDuration,
                minimumClauseDuration: minimumClauseDuration
            )
        }
        let thresholds = adaptivePauseThresholds(words, fallback: pauseThreshold)

        var groups: [[SpeechWordTimestamp]] = []
        var pending: [SpeechWordTimestamp] = []

        func flushAll() {
            guard !pending.isEmpty else { return }
            groups.append(contentsOf: splitLongGroup(
                pending,
                languageCode: languageCode,
                preferredDuration: preferredDuration,
                maximumDuration: maximumDuration,
                minimumClauseDuration: minimumClauseDuration,
                thresholds: thresholds
            ))
            pending.removeAll(keepingCapacity: true)
        }

        for word in words {
            if let previous = pending.last {
                let gap = max(0, word.startSeconds - previous.endSeconds)
                // Chỉ khoảng lặng mạnh là hard boundary. Dấu câu và pause mềm
                // được chấm điểm toàn cụm để hai câu rất ngắn vẫn có thể gộp.
                let audioBackedSilence = gap >= 0.20
                    && (audioEvidence?.confidence(
                        from: previous.endSeconds,
                        to: word.startSeconds
                    ) ?? 0) >= 0.72
                if gap >= thresholds.strong
                    || (gap >= thresholds.soft * 0.85 && audioBackedSilence) {
                    flushAll()
                }
            }

            pending.append(word)
        }
        flushAll()

        return renderedSegments(from: groups, languageCode: languageCode)
    }

    private static func renderedSegments(
        from groups: [[SpeechWordTimestamp]],
        languageCode: String
    ) -> [SRTSegment] {
        groups.enumerated().compactMap { offset, group in
            guard let first = group.first, let last = group.last else { return nil }
            let noSpaces = usesUnspacedScript(
                languageCode,
                text: group.map(\.text).joined()
            )
            let text = joinedText(group.map(\.text), noSpaces: noSpaces)
            guard !text.isEmpty else { return nil }
            return SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: SRTTimecode.makeTiming(start: first.startSeconds, end: last.endSeconds),
                startSeconds: first.startSeconds,
                endSeconds: last.endSeconds,
                text: text
            )
        }
    }

    private static func legacySegments(
        _ words: [SpeechWordTimestamp],
        languageCode: String,
        pauseThreshold: Double,
        preferredDuration: Double,
        maximumDuration: Double,
        minimumClauseDuration: Double
    ) -> [SRTSegment] {
        var groups: [[SpeechWordTimestamp]] = []
        var pending: [SpeechWordTimestamp] = []
        let fixed = PauseThresholds(soft: 0.24, strong: max(0.45, pauseThreshold))

        func flushAll() {
            guard !pending.isEmpty else { return }
            groups.append(contentsOf: splitLongGroup(
                pending,
                languageCode: languageCode,
                preferredDuration: preferredDuration,
                maximumDuration: maximumDuration,
                minimumClauseDuration: minimumClauseDuration,
                thresholds: fixed
            ))
            pending.removeAll(keepingCapacity: true)
        }

        for word in words {
            if let previous = pending.last {
                let gap = max(0, word.startSeconds - previous.endSeconds)
                if gap > pauseThreshold || endsSentence(previous.text) { flushAll() }
            }
            pending.append(word)
            let duration = word.endSeconds - (pending.first?.startSeconds ?? word.startSeconds)
            if endsSentence(word.text) { flushAll() }
            else if duration >= minimumClauseDuration, endsClause(word.text) { flushAll() }
        }
        flushAll()
        return renderedSegments(from: groups, languageCode: languageCode)
    }

    /// Gắn lại cue đã layout vào biên word thật. Nếu tổng nội dung không còn
    /// khớp (provider/schema bất thường), giữ nguyên toàn bộ segment timing.
    static func retime(
        _ segments: [SRTSegment],
        using rawWords: [SpeechWordTimestamp]
    ) -> [SRTSegment] {
        guard !segments.isEmpty else { return [] }
        let words = normalized(rawWords)
        guard !words.isEmpty else { return segments }

        let cueUnits = segments.map { alignmentUnitCount($0.text) }
        let wordUnits = words.map { max(0, alignmentUnitCount($0.text)) }
        let cueTotal = cueUnits.reduce(0, +)
        let wordTotal = wordUnits.reduce(0, +)
        guard cueTotal > 0, wordTotal > 0 else { return segments }
        // Tổng độ dài giống nhau chưa đủ: hai chuỗi bị đổi hoặc mất chữ vẫn có
        // thể cùng count. Chỉ retime khi toàn bộ nội dung thật sự khớp theo thứ tự.
        let cueKey = alignmentKey(segments.map(\.text).joined())
        let wordKey = alignmentKey(words.map(\.text).joined())
        guard cueKey == wordKey, cueTotal == wordTotal else { return segments }

        var output: [SRTSegment] = []
        output.reserveCapacity(segments.count)
        var nextWordIndex = 0
        var consumedWordUnits = 0
        var targetCueUnits = 0

        for (cueIndex, segment) in segments.enumerated() {
            guard nextWordIndex < words.count else { return segments }
            let startWordIndex = nextWordIndex
            targetCueUnits += cueUnits[cueIndex]

            if cueIndex == segments.count - 1 {
                nextWordIndex = words.count
                consumedWordUnits = wordTotal
            } else {
                while nextWordIndex < words.count {
                    consumedWordUnits += wordUnits[nextWordIndex]
                    nextWordIndex += 1
                    if consumedWordUnits >= targetCueUnits { break }
                }
                // Dấu câu tách riêng thuộc cue vừa kết thúc, không được dạt sang cue sau.
                while nextWordIndex < words.count, wordUnits[nextWordIndex] == 0 {
                    nextWordIndex += 1
                }
            }

            let endWordIndex = max(startWordIndex, nextWordIndex - 1)
            let start = words[startWordIndex].startSeconds
            let end = max(start + 0.05, words[endWordIndex].endSeconds)
            output.append(
                SRTSegment(
                    id: segment.id,
                    index: segment.index,
                    timing: SRTTimecode.makeTiming(start: start, end: end),
                    startSeconds: start,
                    endSeconds: end,
                    text: segment.text
                )
            )
        }
        return SRTSegmentEditor.reindexed(output)
    }

    /// Dựng cue từ đúng các word gốc và danh sách chỉ số từ kết thúc cue.
    /// Semantic AI chỉ được cung cấp các chỉ số này; text/timestamp luôn lấy
    /// lại từ `rawWords`, nên provider không thể thêm, bỏ hoặc đổi lời.
    static func makeSegments(
        from rawWords: [SpeechWordTimestamp],
        endingWordIndices: [Int],
        languageCode: String
    ) -> [SRTSegment]? {
        let words = normalized(rawWords)
        guard !words.isEmpty else { return nil }
        let boundaries = Array(Set(endingWordIndices)).sorted()
        guard boundaries == endingWordIndices,
              boundaries.last == words.count - 1,
              boundaries.allSatisfy({ $0 >= 0 && $0 < words.count }) else { return nil }

        var groups: [[SpeechWordTimestamp]] = []
        var start = 0
        for boundary in boundaries {
            guard boundary >= start else { return nil }
            groups.append(Array(words[start...boundary]))
            start = boundary + 1
        }
        guard start == words.count else { return nil }
        return renderedSegments(from: groups, languageCode: languageCode)
    }

    private static func normalized(_ words: [SpeechWordTimestamp]) -> [SpeechWordTimestamp] {
        words.compactMap { word -> SpeechWordTimestamp? in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  word.startSeconds.isFinite,
                  word.endSeconds.isFinite,
                  word.endSeconds > word.startSeconds
            else { return nil }
            return SpeechWordTimestamp(
                text: text,
                startSeconds: max(0, word.startSeconds),
                endSeconds: max(0, word.endSeconds)
            )
        }.sorted {
            $0.startSeconds == $1.startSeconds
                ? $0.endSeconds < $1.endSeconds
                : $0.startSeconds < $1.startSeconds
        }
    }

    private static func joinedText(_ tokens: [String], noSpaces: Bool) -> String {
        var result = ""
        for raw in tokens {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if result.isEmpty || noSpaces || isClosingPunctuation(token) || beginsWithApostrophe(token) {
                result += token
            } else {
                result += " " + token
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trả các Character offset sau từng token provider khi text vẫn là đúng
    /// chuỗi đã dựng từ word timestamp. Layout dùng tập này cho *cue cut*; điểm
    /// xuống dòng bên trong cue vẫn theo Core Text và tailoring ngôn ngữ.
    static func verifiedCueBreakOffsets(
        in text: String,
        using rawWords: [SpeechWordTimestamp],
        languageCode: String
    ) -> Set<Int>? {
        let words = normalized(rawWords)
        guard !words.isEmpty else { return nil }
        let noSpaces = usesUnspacedScript(languageCode, text: text)
        var rebuilt = ""
        var offsets: Set<Int> = []
        for (index, word) in words.enumerated() {
            let token = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if rebuilt.isEmpty || noSpaces || isClosingPunctuation(token) || beginsWithApostrophe(token) {
                rebuilt += token
            } else {
                rebuilt += " " + token
            }
            if index + 1 < words.count { offsets.insert(rebuilt.count) }
        }
        func comparisonKey(_ value: String) -> String {
            value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
        }
        guard comparisonKey(rebuilt) == comparisonKey(text) else { return nil }
        guard words.count > 1 else { return [] }
        return offsets
    }

    /// Pause chỉ là soft evidence cho layout, chỉ dùng khi toàn bộ text khớp
    /// word theo thứ tự. Không đọc waveform/PCM hoặc suy timing từ số chữ.
    static func verifiedCueBoundaryCosts(
        in text: String,
        using rawWords: [SpeechWordTimestamp],
        languageCode: String
    ) -> [Int: Double] {
        guard !SubtitleLinguisticBoundaryContext.isJapanese(languageCode: languageCode, text: text),
              let allowed = verifiedCueBreakOffsets(in: text, using: rawWords, languageCode: languageCode)
        else { return [:] }
        let words = normalized(rawWords)
        let offsets = allowed.sorted()
        guard offsets.count == max(0, words.count - 1) else { return [:] }
        var costs: [Int: Double] = [:]
        for (index, offset) in offsets.enumerated() {
            let gap = max(0, words[index + 1].startSeconds - words[index].endSeconds)
            if gap >= 0.20 { costs[offset] = -min(18, gap * 45) }
        }
        return costs
    }

    private static func usesUnspacedScript(_ languageCode: String, text: String) -> Bool {
        let base = languageCode.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init) ?? ""
        if ["ja", "zh", "yue", "cmn", "th", "lo", "km"].contains(base) { return true }
        guard base.isEmpty || base == "auto" else { return false }
        return text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value)
                || (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0x0E00...0x0EFF).contains($0.value)
                || (0x1780...0x17FF).contains($0.value)
        }
    }

    private static func isClosingPunctuation(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
        } && !"([{<“‘「『【《〈".contains(token.first ?? " ")
    }

    private static func beginsWithApostrophe(_ token: String) -> Bool {
        token.first.map { "'’".contains($0) } ?? false
    }

    private static func endsSentence(_ token: String) -> Bool {
        token.last.map { ".!?…。！？؟۔।॥".contains($0) } ?? false
    }

    private static func endsClause(_ token: String) -> Bool {
        token.last.map { ",;:，、；：—–،؛".contains($0) } ?? false
    }

    /// Ngưỡng lấy từ nhịp nói của chính đoạn audio nhưng luôn nằm trong biên
    /// bảo thủ. Không để một speaker quá nhanh/hay quá chậm đẩy threshold vô hạn.
    private static func adaptivePauseThresholds(
        _ words: [SpeechWordTimestamp],
        fallback: Double
    ) -> PauseThresholds {
        let gaps = zip(words, words.dropFirst()).map {
            max(0, $1.startSeconds - $0.endSeconds)
        }.filter { $0 >= 0.015 && $0 <= 2.5 }.sorted()
        guard !gaps.isEmpty else {
            let soft = min(0.52, max(0.28, fallback))
            return PauseThresholds(soft: soft, strong: min(0.85, max(0.62, soft + 0.20)))
        }

        func percentile(_ fraction: Double) -> Double {
            let position = min(gaps.count - 1, max(0, Int((Double(gaps.count - 1) * fraction).rounded())))
            return gaps[position]
        }
        let median = percentile(0.50)
        let upper = percentile(0.75)
        let high = percentile(0.90)
        let localSoft = median + max(0.16, (upper - median) * 2.2)
        let baseline = min(0.52, max(0.28, fallback))
        let soft = min(0.52, max(0.28, baseline * 0.55 + localSoft * 0.45))
        let strong = min(0.85, max(0.62, max(soft + 0.20, high * 0.92)))
        return PauseThresholds(soft: soft, strong: strong)
    }

    /// Chia tối ưu toàn cụm bằng dynamic programming. Khác cắt tuần tự, cách này
    /// cân bằng cả phần cuối nên câu 6–9 giây không để lại cue cụt một vài từ.
    private static func splitLongGroup(
        _ words: [SpeechWordTimestamp],
        languageCode: String,
        preferredDuration: Double,
        maximumDuration: Double,
        minimumClauseDuration: Double,
        thresholds: PauseThresholds
    ) -> [[SpeechWordTimestamp]] {
        guard words.count > 1 else { return [words] }

        let noSpaces = usesUnspacedScript(languageCode, text: words.map(\.text).joined())
        var text = ""
        var wordEnds: [Int] = []
        var characterCount = 0
        for word in words {
            if !text.isEmpty, !noSpaces, !isClosingPunctuation(word.text), !beginsWithApostrophe(word.text) {
                text += " "
                characterCount += 1
            }
            text += word.text
            characterCount += word.text.count
            wordEnds.append(characterCount)
        }
        let context = SubtitleLinguisticBoundaryContext.isJapanese(languageCode: languageCode, text: text)
            ? nil : SubtitleLinguisticBoundaryContext(text: text, languageCode: languageCode)

        let count = words.count
        var costs = Array(repeating: Double.greatestFiniteMagnitude, count: count + 1)
        var nextIndex = Array(repeating: count, count: count + 1)
        costs[count] = 0

        for start in stride(from: count - 1, through: 0, by: -1) {
            guard !Task.isCancelled else { return [words] }
            for end in start..<count {
                let duration = words[end].endSeconds - words[start].startSeconds
                if duration > maximumDuration + 0.001, end > start { break }
                guard costs[end + 1].isFinite else { continue }

                let isLast = end == count - 1
                var penalty = pow(duration - preferredDuration, 2)
                if duration < 1.4 { penalty += 60 }
                else if duration < 2.0 { penalty += 12 }
                if !isLast {
                    penalty += (context?.cost(at: wordEnds[end]) ?? 0) * 0.15
                    let gap = max(0, words[end + 1].startSeconds - words[end].endSeconds)
                    if endsSentence(words[end].text) { penalty -= 18 }
                    else if duration >= minimumClauseDuration, endsClause(words[end].text) { penalty -= 7 }
                    if gap >= thresholds.strong { penalty -= 18 }
                    else if gap >= thresholds.soft { penalty -= 9 }
                    else if gap >= thresholds.soft * 0.55 { penalty -= 4 }
                }

                let total = penalty + costs[end + 1]
                if total < costs[start] {
                    costs[start] = total
                    nextIndex[start] = end + 1
                }
            }
        }

        guard nextIndex[0] > 0 else { return [words] }
        var result: [[SpeechWordTimestamp]] = []
        var start = 0
        while start < count {
            let end = min(count, max(start + 1, nextIndex[start]))
            result.append(Array(words[start..<end]))
            start = end
        }
        return result
    }

    private static func alignmentKey(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
    }

    private static func alignmentUnitCount(_ text: String) -> Int {
        let key = alignmentKey(text)
        return key.isEmpty
            ? text.filter { !$0.isWhitespace && !$0.isPunctuation }.count
            : key.count
    }
}
