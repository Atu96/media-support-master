import Foundation

enum SubtitleQualitySeverity: Int, Comparable, Equatable, Sendable {
    case notice = 0
    case warning = 1
    case error = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Explicit user repair, independent of the read-only analyzer. Unselected IDs
/// remain stable so unrelated DUB/cache/selection identities are preserved.
enum SubtitleQualityRepair {
    static func repairLayout(
        _ segments: [SRTSegment],
        cueIDs: Set<Int>,
        configuration: SubtitleLayoutConfiguration
    ) -> [SRTSegment] {
        guard !cueIDs.isEmpty, Set(segments.map(\.id)).count == segments.count else { return segments }
        var config = configuration.clamped()
        config.explicitBreakPolicy = .automatic
        var nextID = segments.map(\.id).max() ?? 0
        var output: [SRTSegment] = []
        for cue in segments {
            guard !Task.isCancelled else { return segments }
            guard cueIDs.contains(cue.id), cue.startSeconds.isFinite, cue.endSeconds.isFinite,
                  cue.startSeconds >= 0, cue.endSeconds > cue.startSeconds else {
                output.append(cue); continue
            }
            let pieces = SubtitleLayoutEngine.layoutPieces(cue.text, configuration: config)
            func content(_ text: String) -> String {
                String(text.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace })
            }
            guard !pieces.isEmpty,
                  pieces.allSatisfy({ !$0.issues.contains { $0.code == .lineOverflow || $0.code == .tooManyLines } }),
                  content(pieces.map(\.text).joined()) == content(cue.text),
                  cue.durationSeconds >= Double(pieces.count) * 0.04 else {
                output.append(cue); continue
            }
            if pieces.count == 1 {
                output.append(SRTSegmentEditor.withText(cue, text: pieces[0].text))
                continue
            }
            guard nextID <= Int.max - (pieces.count - 1) else { return segments }
            let weights = pieces.map { max(1, $0.text.filter { !$0.isWhitespace }.count) }
            let total = Double(weights.reduce(0, +))
            var cursor = cue.startSeconds
            var replacements: [SRTSegment] = []
            for (offset, piece) in pieces.enumerated() {
                let end = offset == pieces.count - 1 ? cue.endSeconds
                    : cursor + cue.durationSeconds * Double(weights[offset]) / total
                if offset > 0 { nextID += 1 }
                replacements.append(SRTSegment(id: offset == 0 ? cue.id : nextID, index: cue.index,
                    timing: SRTTimecode.makeTiming(start: cursor, end: end),
                    startSeconds: cursor, endSeconds: end, text: piece.text))
                cursor = end
            }
            // Very uneven piece weights must not produce unreadable micro-cues.
            guard replacements.allSatisfy({ $0.durationSeconds >= 0.04 - 0.000_001 }) else {
                output.append(cue); continue
            }
            output.append(contentsOf: replacements)
        }
        guard !Task.isCancelled else { return segments }
        guard output != segments else { return segments }
        return output.enumerated().map { offset, cue in
            SRTSegment(id: cue.id, index: offset + 1, timing: cue.timing,
                startSeconds: cue.startSeconds, endSeconds: cue.endSeconds, text: cue.text)
        }
    }
}

enum SubtitleQualityIssueCode: String, Equatable, Sendable {
    case emptyText
    case lineOverflow
    case tooManyLines
    case tooFewLines
    case tooFast
    case tooShort
    case tooLong
    case overlap
}

struct SubtitleQualityIssue: Identifiable, Equatable, Sendable {
    let cueID: Int
    let code: SubtitleQualityIssueCode
    let severity: SubtitleQualitySeverity
    let message: String

    var id: String { "\(cueID)-\(code.rawValue)" }
}

/// Phân tích chất lượng không mutate. Kết quả gồm cả lỗi khách quan lẫn gợi ý
/// biên tập; Workspace chỉ đưa lỗi chắc chắn lên toolbar để tránh false positive.
enum SubtitleQualityAnalyzer {
    static func analyze(
        _ segments: [SRTSegment],
        configuration: SubtitleLayoutConfiguration
    ) -> [SubtitleQualityIssue] {
        guard !Task.isCancelled else { return [] }
        let ordered = segments.sorted {
            $0.startSeconds == $1.startSeconds ? $0.index < $1.index : $0.startSeconds < $1.startSeconds
        }
        var issues: [SubtitleQualityIssue] = []

        for (offset, cue) in ordered.enumerated() {
            guard !Task.isCancelled else { return [] }
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                issues.append(issue(cue, .emptyText, .error, "Cue không có nội dung"))
                continue
            }

            let clampedConfiguration = configuration.clamped()
            let hardLines = text.components(separatedBy: "\n")
            if hardLines.count > clampedConfiguration.maxLines {
                issues.append(issue(cue, .tooManyLines, .error, "Vượt \(clampedConfiguration.maxLines) dòng"))
            }
            if clampedConfiguration.requiresTwoLines, clampedConfiguration.maxLines == 2,
               hardLines.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < 2,
               SubtitleLayoutEngine.family(languageCode: configuration.languageCode, text: text) != .japanese {
                issues.append(issue(cue, .tooFewLines, .warning, "Chưa đủ 2 dòng"))
            }
            if hardLines.contains(where: {
                SubtitleLayoutEngine.measuredWidth(
                    of: $0,
                    fontName: clampedConfiguration.fontName,
                    fontSize: clampedConfiguration.fontSize
                ) > clampedConfiguration.containerWidth + 0.5
            }) {
                issues.append(issue(cue, .lineOverflow, .error, "Text tràn vùng an toàn của video"))
            }

            let duration = max(0, cue.endSeconds - cue.startSeconds)
            if duration < 0.65 {
                issues.append(issue(cue, .tooShort, .warning, "Thời lượng dưới 0,65 giây"))
            } else if duration > 7 {
                issues.append(issue(cue, .tooLong, .warning, "Thời lượng trên 7 giây"))
            }

            let readableCount = text.filter { !$0.isWhitespace && !$0.isNewline }.count
            let family = SubtitleLayoutEngine.family(languageCode: configuration.languageCode, text: text)
            let maximumCPS: Double
            switch family {
            case .japanese, .chinese, .korean: maximumCPS = 12
            case .southEastAsian, .brahmic, .spaced: maximumCPS = 20
            }
            if duration > 0, Double(readableCount) / duration > maximumCPS {
                issues.append(issue(cue, .tooFast, .warning, "Tốc độ đọc quá nhanh"))
            }

            if offset + 1 < ordered.count, cue.endSeconds > ordered[offset + 1].startSeconds + 0.001 {
                issues.append(issue(cue, .overlap, .error, "Chồng timing với cue kế tiếp"))
            }
        }

        return issues.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.cueID != $1.cueID { return $0.cueID < $1.cueID }
            return $0.code.rawValue < $1.code.rawValue
        }
    }

    private static func issue(
        _ cue: SRTSegment,
        _ code: SubtitleQualityIssueCode,
        _ severity: SubtitleQualitySeverity,
        _ message: String
    ) -> SubtitleQualityIssue {
        SubtitleQualityIssue(cueID: cue.id, code: code, severity: severity, message: message)
    }
}
