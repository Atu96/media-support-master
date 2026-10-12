import Foundation

enum MaziaoDubbingStyle: String, CaseIterable, Identifiable, Sendable {
    case paragraphs, cues
    var id: String { rawValue }
    var label: String { self == .paragraphs ? "Đoạn liền mạch" : "Từng cue" }
}

struct MaziaoContextGroup: Sendable {
    let cue: SRTSegment
    let sourceIDs: Set<Int>
}

enum MaziaoContextPlanningError: LocalizedError, Equatable {
    case invalidCues, tooLarge
    var errorDescription: String? {
        L10n.string(self == .invalidCues
            ? "Không thể gom đoạn: phụ đề có cue rỗng, ID trùng hoặc thời gian chồng/sai. Hãy sửa QC trước."
            : "Phụ đề quá lớn để gom đoạn trong một lượt. Hãy chia nội dung thành các phần ngắn hơn.")
    }
}

/// Cheap text/timeline projection only. A DUB paragraph has its own identity/span;
/// it does not split the generated audio or mutate the original subtitle cues.
enum MaziaoContextPlanner {
    static let maximumGap = 1.2
    static let targetCharacters = 240
    static let maximumCharacters = 900
    static let maximumSpan = 30.0
    static let maximumCues = 24
    static let minimumContextCharacters = 140

    static func groups(_ cues: [SRTSegment], language: String) throws -> [MaziaoContextGroup] {
        guard cues.count <= 20_000 else { throw MaziaoContextPlanningError.tooLarge }
        guard Set(cues.map(\.id)).count == cues.count else { throw MaziaoContextPlanningError.invalidCues }
        let compact = language.lowercased().hasPrefix("ja") || language.lowercased().hasPrefix("zh")
        let separator = compact ? "" : " "
        var output: [MaziaoContextGroup] = [], current: [SRTSegment] = [], characters = 0
        var previousEnd = -Double.infinity
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map { DubbingFingerprint.spokenText($0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: separator)
            let index = output.count + 1
            output.append(.init(cue: .init(id: index, index: index,
                timing: SRTTimecode.makeTiming(start: first.startSeconds, end: last.endSeconds),
                startSeconds: first.startSeconds, endSeconds: last.endSeconds, text: text),
                sourceIDs: Set(current.map(\.id))))
            current.removeAll(keepingCapacity: true); characters = 0
        }
        for cue in cues {
            try Task.checkCancellation()
            let text = DubbingFingerprint.spokenText(cue.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard cue.startSeconds.isFinite, cue.endSeconds.isFinite, cue.startSeconds >= 0,
                  cue.endSeconds > cue.startSeconds, cue.startSeconds >= previousEnd - 0.001,
                  !text.isEmpty else { throw MaziaoContextPlanningError.invalidCues }
            if let first = current.first, let last = current.last,
               cue.startSeconds - last.endSeconds > maximumGap
                || cue.endSeconds - first.startSeconds > maximumSpan
                || characters + text.count > maximumCharacters || current.count >= maximumCues { flush() }
            current.append(cue); characters += text.count + (current.count > 1 ? separator.count : 0)
            previousEnd = cue.endSeconds
            if characters >= targetCharacters && endsSentence(text) { flush() }
        }
        flush()
        var combined: [MaziaoContextGroup] = []
        for group in output {
            if let last = combined.last,
               min(last.cue.text.count, group.cue.text.count) < minimumContextCharacters,
               group.cue.startSeconds - last.cue.endSeconds <= maximumGap,
               group.cue.endSeconds - last.cue.startSeconds <= maximumSpan,
               last.sourceIDs.count + group.sourceIDs.count <= maximumCues,
               last.cue.text.count + group.cue.text.count + separator.count <= maximumCharacters {
                combined.removeLast()
                let text = last.cue.text + separator + group.cue.text
                combined.append(.init(cue: .init(id: 0, index: 0,
                    timing: SRTTimecode.makeTiming(start: last.cue.startSeconds, end: group.cue.endSeconds),
                    startSeconds: last.cue.startSeconds, endSeconds: group.cue.endSeconds, text: text),
                    sourceIDs: last.sourceIDs.union(group.sourceIDs)))
            } else { combined.append(group) }
        }
        return combined.enumerated().map { index, group in
            .init(cue: .init(id: index + 1, index: index + 1, timing: group.cue.timing,
                startSeconds: group.cue.startSeconds, endSeconds: group.cue.endSeconds, text: group.cue.text),
                sourceIDs: group.sourceIDs)
        }
    }

    private static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'”’」』】)）"))
        guard let last = trimmed.last else { return false }
        return ".!?。！？…".contains(last)
    }

    /// Stable old IDs are supplied to the existing alias/rate migration seam.
    /// Final IDs remain consecutive DUB paragraph IDs, separate from SUB IDs.
    static func cachePreservation(previous: [SRTSegment], updated: [SRTSegment]) -> [SRTSegment] {
        func key(_ cue: SRTSegment) -> String {
            "\(cue.startSeconds)\u{001F}\(cue.endSeconds)\u{001F}\(cue.text)"
        }
        let byKey = Dictionary(previous.map { (key($0), $0.id) }, uniquingKeysWith: { a, _ in a })
        return updated.enumerated().map { index, cue in
            .init(id: byKey[key(cue)] ?? -(index + 1), index: cue.index, timing: cue.timing,
                startSeconds: cue.startSeconds, endSeconds: cue.endSeconds, text: cue.text)
        }
    }
}
