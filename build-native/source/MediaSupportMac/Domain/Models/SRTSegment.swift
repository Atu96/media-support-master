import Foundation

struct SRTSegment: Identifiable, Sendable {
    let id: Int
    let index: Int
    let timing: String
    let startSeconds: Double
    let endSeconds: Double
    let text: String

    var startLabel: String {
        SRTTimecode.format(startSeconds)
    }

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    /// Điểm seek khi bấm dòng ở tab chỉnh sửa — lệch vài giây vào trong cue để sub overlay hiện rõ (qua fade-in).
    func editPreviewSeekTime(leadIn: Double = 2.0) -> Double {
        let duration = durationSeconds
        if duration <= 0.25 {
            return startSeconds
        }
        let inset = min(leadIn, duration * 0.4)
        return min(endSeconds - 0.08, startSeconds + max(0.4, inset))
    }
}

extension Array where Element == SRTSegment {
    /// Segment đang phát tại `time` — binary search O(log n), biên cuối +40ms.
    func segment(at time: Double) -> SRTSegment? {
        guard !isEmpty else { return nil }

        var low = 0
        var high = count - 1

        while low <= high {
            let mid = (low + high) / 2
            let candidate = self[mid]

            if time < candidate.startSeconds {
                high = mid - 1
            } else if time > candidate.endSeconds + 0.04 {
                low = mid + 1
            } else {
                return candidate
            }
        }
        return nil
    }

    func segmentID(at time: Double) -> Int? {
        segment(at: time)?.id
    }
}