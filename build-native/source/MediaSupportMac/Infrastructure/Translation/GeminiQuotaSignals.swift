import Foundation

/// Marker từ `translate_srt_gemini.py` khi key hết quota / 429.
enum GeminiQuotaSignals {
    static let marker = "MSM_GEMINI_QUOTA_EXCEEDED"

    static let logNeedles = [
        marker,
        "RESOURCE_EXHAUSTED",
        "quota exceeded",
        "exceeded your current quota",
        "rate limit",
        "429",
    ]

    static func matches(_ line: String) -> Bool {
        let lower = line.lowercased()
        if line.contains(marker) { return true }
        return logNeedles.dropFirst().contains { lower.contains($0.lowercased()) }
    }
}