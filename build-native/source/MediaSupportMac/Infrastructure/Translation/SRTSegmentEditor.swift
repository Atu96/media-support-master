import Foundation

enum SRTSegmentEditor {
    static func reindexed(_ segments: [SRTSegment]) -> [SRTSegment] {
        segments.enumerated().map { offset, segment in
            SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: segment.timing,
                startSeconds: segment.startSeconds,
                endSeconds: segment.endSeconds,
                text: segment.text
            )
        }
    }

    static func withText(_ segment: SRTSegment, text: String) -> SRTSegment {
        SRTSegment(
            id: segment.id,
            index: segment.index,
            timing: segment.timing,
            startSeconds: segment.startSeconds,
            endSeconds: segment.endSeconds,
            text: text
        )
    }

    // MARK: - Timing API (móng timeline / chỉnh tay — pure, không side-effect)

    /// Tạo cue với timing mới (start < end, cả hai ≥ 0).
    static func withTiming(_ segment: SRTSegment, start: Double, end: Double) -> SRTSegment {
        let s = max(0, start)
        let e = max(s + 0.04, end)
        return SRTSegment(
            id: segment.id,
            index: segment.index,
            timing: SRTTimecode.makeTiming(start: s, end: e),
            startSeconds: s,
            endSeconds: e,
            text: segment.text
        )
    }

    /// Dời cả cue (giữ duration). `minStart` / `maxEnd` tuỳ chọn (vd cạnh cue trước/sau).
    static func move(
        in segments: [SRTSegment],
        id: Int,
        delta: Double,
        minStart: Double = 0,
        maxEnd: Double? = nil
    ) -> [SRTSegment]? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let seg = segments[idx]
        let duration = seg.durationSeconds
        guard duration > 0.04 else { return nil }
        var newStart = seg.startSeconds + delta
        var newEnd = seg.endSeconds + delta
        if newStart < minStart {
            let shift = minStart - newStart
            newStart += shift
            newEnd += shift
        }
        if let maxEnd, newEnd > maxEnd {
            let shift = newEnd - maxEnd
            newStart -= shift
            newEnd -= shift
            if newStart < minStart { return nil }
        }
        var updated = segments
        updated[idx] = withTiming(seg, start: newStart, end: newEnd)
        return updated
    }

    /// Kéo mép trái (in). Giữ end; start không vượt end − minDuration.
    static func trimStart(
        in segments: [SRTSegment],
        id: Int,
        newStart: Double,
        minDuration: Double = 0.04,
        floor: Double = 0
    ) -> [SRTSegment]? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let seg = segments[idx]
        let s = min(max(floor, newStart), seg.endSeconds - minDuration)
        guard abs(s - seg.startSeconds) > 0.000_5 else { return nil }
        var updated = segments
        updated[idx] = withTiming(seg, start: s, end: seg.endSeconds)
        return updated
    }

    /// Kéo mép phải (out). Giữ start; end không nhỏ hơn start + minDuration.
    static func trimEnd(
        in segments: [SRTSegment],
        id: Int,
        newEnd: Double,
        minDuration: Double = 0.04,
        ceiling: Double? = nil
    ) -> [SRTSegment]? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let seg = segments[idx]
        var e = max(seg.startSeconds + minDuration, newEnd)
        if let ceiling {
            e = min(e, ceiling)
            guard e >= seg.startSeconds + minDuration else { return nil }
        }
        guard abs(e - seg.endSeconds) > 0.000_5 else { return nil }
        var updated = segments
        updated[idx] = withTiming(seg, start: seg.startSeconds, end: e)
        return updated
    }

    /// Gộp từ hai cue liền kề — giữ nguyên span timeline [start đầu → end cuối].
    static func mergeAdjacent(in segments: [SRTSegment], ids: Set<Int>) -> [SRTSegment]? {
        guard ids.count >= 2 else { return nil }

        let selectedIndices = segments.indices.filter { ids.contains(segments[$0].id) }
        guard selectedIndices.count == ids.count,
              let firstIndex = selectedIndices.first,
              let lastIndex = selectedIndices.last,
              selectedIndices == Array(firstIndex...lastIndex) else {
            return nil
        }

        let selected = segments[firstIndex...lastIndex]
        guard let first = selected.first, let last = selected.last else { return nil }

        let mergedText = selected.map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let merged = SRTSegment(
            id: first.id,
            index: first.index,
            timing: SRTTimecode.makeTiming(start: first.startSeconds, end: last.endSeconds),
            startSeconds: first.startSeconds,
            endSeconds: last.endSeconds,
            text: mergedText
        )

        var updated = segments
        updated.replaceSubrange(firstIndex...lastIndex, with: [merged])
        return reindexed(updated)
    }

    static func delete(in segments: [SRTSegment], id: Int) -> [SRTSegment]? {
        delete(in: segments, ids: [id])
    }

    /// Xóa một hoặc nhiều cue đã chọn. Mảng rỗng là trạng thái hợp lệ và vẫn
    /// được lưu/Undo như mọi edit khác.
    static func delete(in segments: [SRTSegment], ids: Set<Int>) -> [SRTSegment]? {
        guard !ids.isEmpty else { return nil }
        let updated = segments.filter { !ids.contains($0.id) }
        guard updated.count < segments.count else { return nil }
        return reindexed(updated)
    }

    /// Tách một cue — tổng span [start, end] không đổi. EN: tách theo nguyên câu + time theo tỷ lệ chữ.
    static func split(
        in segments: [SRTSegment],
        id: Int,
        at splitTime: Double? = nil,
        languageCode: String? = nil
    ) -> [SRTSegment]? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let segment = segments[idx]
        let duration = segment.endSeconds - segment.startSeconds
        guard duration > 0.05 else { return nil }

        let lang = normalizedLanguageCode(languageCode)
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let useEnglishSentences = lang == "en"
            || (lang != "ja" && SRTEnglishSentenceSplitter.looksEnglish(trimmed))

        let firstText: String
        let secondText: String
        let textRatio: Double

        if useEnglishSentences, let sentenceSplit = SRTEnglishSentenceSplitter.splitNearMiddle(trimmed) {
            (firstText, secondText, textRatio) = sentenceSplit
        } else if let splitTime {
            textRatio = duration > 0 ? (splitTime - segment.startSeconds) / duration : 0.5
            let split = splitText(trimmed, ratio: textRatio)
            firstText = split.0
            secondText = split.1
        } else {
            textRatio = 0.5
            let split = splitText(trimmed, ratio: 0.5)
            firstText = split.0
            secondText = split.1
        }

        let midpoint = segment.startSeconds + duration * min(max(textRatio, 0.05), 0.95)
        guard midpoint > segment.startSeconds, midpoint < segment.endSeconds else { return nil }

        let first = SRTSegment(
            id: segment.id,
            index: segment.index,
            timing: SRTTimecode.makeTiming(start: segment.startSeconds, end: midpoint),
            startSeconds: segment.startSeconds,
            endSeconds: midpoint,
            text: firstText
        )
        let second = SRTSegment(
            id: segment.id + 1,
            index: segment.index + 1,
            timing: SRTTimecode.makeTiming(start: midpoint, end: segment.endSeconds),
            startSeconds: midpoint,
            endSeconds: segment.endSeconds,
            text: secondText
        )

        var updated = segments
        updated[idx] = first
        updated.insert(second, at: idx + 1)
        return reindexed(updated)
    }

    private static func splitText(_ text: String, ratio: Double) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let clamped = min(max(ratio, 0.05), 0.95)
        let target = max(1, Int((Double(trimmed.count) * clamped).rounded()))
        let pivot = nearestWordBoundary(in: trimmed, near: target)

        let first = String(trimmed.prefix(pivot)).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(trimmed.dropFirst(pivot)).trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty || second.isEmpty {
            let half = trimmed.count / 2
            return (
                String(trimmed.prefix(half)).trimmingCharacters(in: .whitespacesAndNewlines),
                String(trimmed.dropFirst(half)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return (first, second)
    }

    private static func nearestWordBoundary(in text: String, near index: Int) -> Int {
        let clamped = min(max(index, 1), max(1, text.count - 1))
        let chars = Array(text)
        var best = clamped
        var bestDistance = Int.max

        for candidate in [clamped] + stride(from: clamped - 12, through: clamped + 12, by: 1) {
            guard candidate > 0, candidate < chars.count else { continue }
            if chars[candidate].isWhitespace {
                let distance = abs(candidate - clamped)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }
        }
        return best
    }

    private static func normalizedLanguageCode(_ code: String?) -> String {
        let raw = (code ?? "auto").lowercased().split(separator: "-").first.map(String.init) ?? "auto"
        return raw
    }
}
