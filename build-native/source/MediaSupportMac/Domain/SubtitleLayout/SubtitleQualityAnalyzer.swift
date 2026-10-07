import Foundation

enum SubtitleQualitySeverity: Int, Comparable, Equatable, Sendable {
    case notice = 0
    case warning = 1
    case error = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SubtitleQualityIssueCode: String, Equatable, Sendable {
    case emptyText
    case lineOverflow
    case tooManyLines
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
        let ordered = segments.sorted {
            $0.startSeconds == $1.startSeconds ? $0.index < $1.index : $0.startSeconds < $1.startSeconds
        }
        var issues: [SubtitleQualityIssue] = []

        for (offset, cue) in ordered.enumerated() {
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
