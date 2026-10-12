import Foundation

enum SubtitleEvidenceSource: String, Sendable { case audio, ocr }

struct SubtitleEvidenceGroup: Identifiable, Sendable {
    let id: Int
    let current: [SRTSegment]
    let candidate: [SRTSegment]
    let start: Double
    let end: Double
    let currentText: String
    let candidateText: String
    let differs: Bool

    init(id: Int, current: [SRTSegment], candidate: [SRTSegment]) {
        self.id = id; self.current = current; self.candidate = candidate
        start = (current + candidate).map(\.startSeconds).min() ?? 0
        end = (current + candidate).map(\.endSeconds).max() ?? 0
        currentText = current.map(\.text).joined(separator: "\n")
        candidateText = candidate.map(\.text).joined(separator: "\n")
        differs = currentText.filter { !$0.isWhitespace } != candidateText.filter { !$0.isWhitespace }
            || current.map(\.timing) != candidate.map(\.timing)
    }
}

enum SubtitleEvidenceError: LocalizedError {
    case invalidTiming, tooLarge, scriptMismatch
    var errorDescription: String? {
        switch self {
        case .invalidTiming: L10n.string("Không thể đối chiếu: có cue rỗng, chồng thời gian hoặc thời gian không hợp lệ.")
        case .tooLarge: L10n.string("Phụ đề quá dài cho một lượt đối chiếu. Hãy chia thành các phần ngắn hơn.")
        case .scriptMismatch: L10n.string("Văn bản chưa khớp đủ với các cue hiện có. Giữ nguyên phụ đề; hãy kiểm tra nội dung, ngôn ngữ hoặc khớp lại từ âm thanh.")
        }
    }
}

/// Time-connected groups handle one-to-many cue boundaries without inventing word times.
/// Choices default to the current transcript, including unmatched candidate intervals.
enum SubtitleEvidenceComparison {
    static func validate(_ cues: [SRTSegment]) throws {
        guard !cues.isEmpty, cues.count <= 20_000 else { throw SubtitleEvidenceError.tooLarge }
        guard cues.reduce(0, { $0 + $1.text.count }) <= 2_000_000 else { throw SubtitleEvidenceError.tooLarge }
        var previousEnd = -Double.infinity
        for cue in cues {
            try Task.checkCancellation()
            guard cue.startSeconds.isFinite, cue.endSeconds.isFinite, cue.startSeconds >= 0,
                  cue.endSeconds > cue.startSeconds,
                  cue.startSeconds >= previousEnd - 0.001,
                  !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SubtitleEvidenceError.invalidTiming
            }
            previousEnd = cue.endSeconds
        }
    }

    static func groups(current: [SRTSegment], candidate: [SRTSegment]) throws -> [SubtitleEvidenceGroup] {
        try validate(current); try validate(candidate)
        let items = (current.map { ($0, false) } + candidate.map { ($0, true) })
            .sorted { $0.0.startSeconds < $1.0.startSeconds }
        var result: [SubtitleEvidenceGroup] = []
        var a: [SRTSegment] = [], b: [SRTSegment] = [], upper = -Double.infinity
        func flush() {
            guard !a.isEmpty || !b.isEmpty else { return }
            result.append(SubtitleEvidenceGroup(id: result.count, current: a, candidate: b))
            a.removeAll(keepingCapacity: true); b.removeAll(keepingCapacity: true)
        }
        for (cue, secondary) in items {
            try Task.checkCancellation()
            if cue.startSeconds >= upper { flush() }
            upper = max((a.isEmpty && b.isEmpty) ? cue.endSeconds : upper, cue.endSeconds)
            if secondary { b.append(cue) } else { a.append(cue) }
        }
        flush()
        return result
    }

    static func selected(_ groups: [SubtitleEvidenceGroup], candidateIDs: Set<Int>) throws -> [SRTSegment] {
        SRTSegmentEditor.reindexed(try planned(groups, candidateIDs: candidateIDs))
    }

    static func planned(_ groups: [SubtitleEvidenceGroup], candidateIDs: Set<Int>) throws -> [SRTSegment] {
        var nextCandidateID = -1
        let output = groups.flatMap { group -> [SRTSegment] in
            guard candidateIDs.contains(group.id) else { return group.current }
            return group.candidate.map { cue in
                defer { nextCandidateID -= 1 }
                return SRTSegment(id: nextCandidateID, index: cue.index, timing: cue.timing,
                    startSeconds: cue.startSeconds, endSeconds: cue.endSeconds, text: cue.text)
            }
        }
        try validate(output)
        return output
    }
}

/// Uses whole existing cue spans as coarse evidence. It must not pretend that saved SRT
/// contains word timestamps. Every original cue must have a unique, complete mapping.
enum ExistingCueScriptMapper {
    static func replace(script: String, cues: [SRTSegment], language: String) throws -> [SRTSegment] {
        try SubtitleEvidenceComparison.validate(cues)
        guard script.count <= 200_000, cues.reduce(0, { $0 + $1.text.count }) <= 200_000 else {
            throw SubtitleEvidenceError.tooLarge
        }
        let tokens = cues.map { SpeechWordTimestamp(text: $0.text,
            startSeconds: $0.startSeconds, endSeconds: $0.endSeconds) }
        let aligned: [SpeechWordTimestamp]
        do { aligned = try NativeScriptAligner.align(script: script, tokens: tokens, language: language) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SubtitleEvidenceError.scriptMismatch }
        var texts = [String](repeating: "", count: cues.count), index = 0
        for word in aligned {
            try Task.checkCancellation()
            while index < cues.count && cues[index].endSeconds < word.endSeconds - 0.001 { index += 1 }
            guard index < cues.count,
                  abs(cues[index].startSeconds - word.startSeconds) <= 0.001,
                  abs(cues[index].endSeconds - word.endSeconds) <= 0.001 else {
                throw SubtitleEvidenceError.scriptMismatch
            }
            texts[index] += word.text
        }
        guard texts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              texts.joined().filter({ !$0.isWhitespace }) == script.filter({ !$0.isWhitespace }) else {
            throw SubtitleEvidenceError.scriptMismatch
        }
        return zip(cues, texts).map { cue, text in
            SRTSegment(id: cue.id, index: cue.index, timing: cue.timing,
                startSeconds: cue.startSeconds, endSeconds: cue.endSeconds,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
