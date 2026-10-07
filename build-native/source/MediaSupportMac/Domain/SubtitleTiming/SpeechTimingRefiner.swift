import Foundation

struct SpeechActivityInterval: Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double

    var duration: Double { max(0, endSeconds - startSeconds) }
}

/// Tinh chỉnh mép cue bằng vùng giọng nói đã được classifier xác nhận.
/// Không tạo/xóa text và luôn giữ timing provider nếu classifier không chắc chắn.
enum SpeechTimingRefiner {
    static func normalizedActivity(
        _ intervals: [SpeechActivityInterval],
        edgePadding: Double = 0.08,
        mergeGap: Double = 0.30
    ) -> [SpeechActivityInterval] {
        let prepared = intervals.compactMap { interval -> SpeechActivityInterval? in
            guard interval.startSeconds.isFinite,
                  interval.endSeconds.isFinite,
                  interval.endSeconds > interval.startSeconds
            else { return nil }
            return SpeechActivityInterval(
                startSeconds: max(0, interval.startSeconds - edgePadding),
                endSeconds: interval.endSeconds + edgePadding,
                confidence: min(1, max(0, interval.confidence))
            )
        }.sorted { lhs, rhs in
            lhs.startSeconds == rhs.startSeconds
                ? lhs.endSeconds < rhs.endSeconds
                : lhs.startSeconds < rhs.startSeconds
        }
        guard !prepared.isEmpty else { return [] }

        var merged: [SpeechActivityInterval] = []
        for interval in prepared {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.startSeconds <= last.endSeconds + mergeGap {
                merged[merged.count - 1] = SpeechActivityInterval(
                    startSeconds: last.startSeconds,
                    endSeconds: max(last.endSeconds, interval.endSeconds),
                    confidence: max(last.confidence, interval.confidence)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func refine(
        _ segments: [SRTSegment],
        using rawActivity: [SpeechActivityInterval],
        searchTolerance: Double = 0.35,
        maximumEdgeAdjustment: Double = 0.90
    ) -> [SRTSegment] {
        guard !segments.isEmpty else { return [] }
        let activity = normalizedActivity(rawActivity)
        guard !activity.isEmpty else { return segments }

        let ordered = segments.sorted {
            $0.startSeconds == $1.startSeconds
                ? $0.endSeconds < $1.endSeconds
                : $0.startSeconds < $1.startSeconds
        }
        var refined: [SRTSegment] = []
        refined.reserveCapacity(ordered.count)
        var firstRelevantActivity = 0

        for (index, segment) in ordered.enumerated() {
            while firstRelevantActivity < activity.count,
                  activity[firstRelevantActivity].endSeconds < segment.startSeconds - searchTolerance {
                firstRelevantActivity += 1
            }
            var cursor = firstRelevantActivity
            var first: SpeechActivityInterval?
            var last: SpeechActivityInterval?
            var startsInsideSpeech = false
            var endsInsideSpeech = false
            while cursor < activity.count,
                  activity[cursor].startSeconds <= segment.endSeconds + searchTolerance {
                let interval = activity[cursor]
                if interval.endSeconds >= segment.startSeconds - searchTolerance {
                    if first == nil { first = interval }
                    last = interval
                    startsInsideSpeech = startsInsideSpeech
                        || (interval.startSeconds <= segment.startSeconds
                            && segment.startSeconds <= interval.endSeconds)
                    endsInsideSpeech = endsInsideSpeech
                        || (interval.startSeconds <= segment.endSeconds
                            && segment.endSeconds <= interval.endSeconds)
                }
                cursor += 1
            }
            guard let first, let last else {
                refined.append(segment)
                continue
            }

            var start = segment.startSeconds
            var end = segment.endSeconds

            let startDelta = first.startSeconds - start
            if (!startsInsideSpeech && abs(startDelta) <= maximumEdgeAdjustment)
                || (startDelta < 0 && abs(startDelta) <= searchTolerance) {
                start = first.startSeconds
            }

            let endDelta = last.endSeconds - end
            if (!endsInsideSpeech && abs(endDelta) <= maximumEdgeAdjustment)
                || (endDelta > 0 && abs(endDelta) <= searchTolerance) {
                end = last.endSeconds
            }

            if index > 0 {
                start = max(start, refined[index - 1].endSeconds)
            }
            if index + 1 < ordered.count {
                end = min(end, ordered[index + 1].startSeconds)
            }

            guard end - start >= 0.12 else {
                refined.append(segment)
                continue
            }
            refined.append(
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
        return SRTSegmentEditor.reindexed(refined)
    }
}
