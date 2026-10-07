import Foundation

enum SRTEnglishSentenceSplitter {
    private static let abbrevPattern = #"\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|i\.e|e\.g|U\.S|U\.K|No|St)\.$"#

    /// Có vẻ là tiếng Anh (có space + chữ Latin) khi chưa có mã ngôn ngữ.
    static func looksEnglish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" ") else { return false }
        let latin = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        return Double(latin) / Double(max(1, trimmed.count)) > 0.7
    }

    /// Tách tại ranh giới câu gần giữa đoạn. Trả về (câu 1, câu 2, tỷ lệ độ dài câu 1).
    static func splitNearMiddle(_ text: String) -> (String, String, Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        let boundaries = sentenceBoundaries(in: trimmed)
        guard boundaries.count >= 1 else { return nil }

        let target = trimmed.count / 2
        guard let pivot = boundaries.min(by: { abs($0 - target) < abs($1 - target) }),
              pivot > 0, pivot < trimmed.count else {
            return nil
        }

        let first = String(trimmed.prefix(pivot)).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(trimmed.dropFirst(pivot)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !second.isEmpty else { return nil }

        let ratio = Double(pivot) / Double(trimmed.count)
        return (first, second, min(max(ratio, 0.08), 0.92))
    }

    private static func sentenceBoundaries(in text: String) -> [Int] {
        var result: [Int] = []
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        nsText.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, substringRange, _, _ in
            let end = substringRange.location + substringRange.length
            if end > 0, end <= text.count {
                result.append(end)
            }
        }

        if result.count >= 2 {
            return Array(result.dropLast())
        }

        return fallbackPunctuationBoundaries(in: text)
    }

    private static func fallbackPunctuationBoundaries(in text: String) -> [Int] {
        var result: [Int] = []
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "." || ch == "!" || ch == "?" {
                let prefix = String(chars[0...index])
                if !isAbbreviationTail(prefix) {
                    var end = index + 1
                    while end < chars.count, chars[end].isWhitespace {
                        end += 1
                    }
                    if end > 0, end <= chars.count {
                        result.append(end)
                    }
                }
            }
            index += 1
        }
        return result
    }

    private static func isAbbreviationTail(_ prefix: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: abbrevPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(prefix.startIndex..., in: prefix)
        return regex.firstMatch(in: prefix, options: [], range: range) != nil
    }
}