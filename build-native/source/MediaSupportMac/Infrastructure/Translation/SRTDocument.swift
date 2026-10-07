import Foundation

struct SRTBlock: Sendable {
    let timing: String
    let text: String
}

enum SRTDocument {
    static func parseSegments(_ content: String) -> [SRTSegment] {
        parse(content).enumerated().compactMap { offset, block in
            let parts = block.timing.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = SRTTimecode.parse(parts[0]),
                  let end = SRTTimecode.parse(parts[1]) else {
                return nil
            }
            return SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: block.timing,
                startSeconds: start,
                endSeconds: end,
                text: block.text
            )
        }
    }

    static func renderSRT(_ segments: [SRTSegment]) -> String {
        segments.map { segment in
            "\(segment.index)\n\(segment.timing)\n\(segment.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    /// Bản TXT để đọc/biên tập, không phải bản subtitle: bỏ timecode và ranh giới cue,
    /// nối text thành các đoạn văn theo câu hoặc khoảng nghỉ tự nhiên.
    /// `includeTime` chỉ giữ lại cho export kỹ thuật cũ; các lệnh Xuất TXT của app dùng mặc định sạch.
    static func renderTXT(_ segments: [SRTSegment], includeTime: Bool = false) -> String {
        if includeTime {
            return segments.map { "\($0.timing)\n\($0.text)" }.joined(separator: "\n\n")
        }
        return renderReadingText(segments)
    }

    private static func renderReadingText(_ segments: [SRTSegment]) -> String {
        let ordered = segments.sorted {
            $0.startSeconds == $1.startSeconds ? $0.index < $1.index : $0.startSeconds < $1.startSeconds
        }
        guard !ordered.isEmpty else { return "" }

        let paragraphTarget = 360
        let pauseCreatesParagraph = 1.25
        var paragraphs: [String] = []
        var paragraph = ""

        for (index, segment) in ordered.enumerated() {
            let text = normalizeReadingText(segment.text)
            guard !text.isEmpty else { continue }
            paragraph = appendReadingText(text, to: paragraph)

            let isSentenceEnd = text.last.map { ".!?…。！？".contains($0) } ?? false
            let gapAfter = index + 1 < ordered.count
                ? ordered[index + 1].startSeconds - segment.endSeconds
                : 0
            if isSentenceEnd, (paragraph.count >= paragraphTarget || gapAfter >= pauseCreatesParagraph) {
                paragraphs.append(paragraph)
                paragraph = ""
            }
        }

        if !paragraph.isEmpty { paragraphs.append(paragraph) }
        return paragraphs.joined(separator: "\n\n") + (paragraphs.isEmpty ? "" : "\n")
    }

    private static func normalizeReadingText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendReadingText(_ text: String, to paragraph: String) -> String {
        guard !paragraph.isEmpty else { return text }
        // Dấu đóng câu/ngoặc không có space trước; tiếng CJK cũng không ép space giữa ký tự.
        guard let first = text.first, let last = paragraph.last else { return paragraph + text }
        if "，。！？、；：,.!?;:)]}»”』）】".contains(first)
            || "「『（【([{".contains(last)
            || (isIdeographic(first) && isIdeographic(last)) {
            return paragraph + text
        }
        return paragraph + " " + text
    }

    private static func isIdeographic(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value)
                || (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
        }
    }

    static func parse(_ content: String) -> [SRTBlock] {
        let blocks = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
        var result: [SRTBlock] = []
        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count >= 3, lines[1].contains("-->") else { continue }
            let timing = lines[1]
            let text = lines.dropFirst(2).joined(separator: "\n")
            result.append(SRTBlock(timing: timing, text: text))
        }
        return result
    }

    static func write(blocks: [SRTBlock], translated: [String], to url: URL) throws {
        guard blocks.count == translated.count else {
            throw SRTDocumentError.countMismatch
        }
        var output = ""
        for (index, block) in blocks.enumerated() {
            let candidate = translated[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let text = candidate.isEmpty ? block.text : candidate
            output += "\(index + 1)\n\(block.timing)\n\(text)\n\n"
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum SRTDocumentError: LocalizedError {
    case emptyInput
    case countMismatch

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Không đọc được nội dung SRT."
        case .countMismatch: "Số block dịch không khớp SRT gốc."
        }
    }
}
