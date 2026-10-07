import Foundation

enum WhisperProgressParser {
    /// `MSM_PROGRESS:45` hoặc `progress =  45%` từ whisper-cli --print-progress.
    static func percent(from logLine: String) -> Int? {
        let trimmed = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("MSM_PROGRESS:") {
            let raw = trimmed.dropFirst("MSM_PROGRESS:".count)
            if let value = Int(raw), (0...100).contains(value) { return value }
        }
        guard let range = trimmed.range(of: #"progress\s*=\s*(\d+)%"#, options: .regularExpression) else {
            return nil
        }
        let match = String(trimmed[range])
        let digits = match.filter(\.isNumber)
        guard let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }
}