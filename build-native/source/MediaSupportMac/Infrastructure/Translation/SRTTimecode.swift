import Foundation

enum SRTTimecode {
    static func parse(_ token: String) -> Double? {
        let cleaned = token.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func formatPrecise(_ seconds: Double) -> String {
        let totalMs = max(0, Int((seconds * 1000).rounded()))
        let h = totalMs / 3_600_000
        let m = (totalMs % 3_600_000) / 60_000
        let s = (totalMs % 60_000) / 1_000
        let ms = totalMs % 1_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    static func makeTiming(start: Double, end: Double) -> String {
        "\(formatPrecise(start)) --> \(formatPrecise(end))"
    }
}