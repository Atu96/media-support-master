import Foundation

struct MediaLanguageRecord: Codable, Sendable {
    let language: String
    let confidence: Double?
    let detector: String
    let media: String?
    let detectedAt: String?

    static let sidecarExtension = "msm-lang.json"

    static func sidecarURL(for mediaOrSRT: URL) -> URL {
        let base = mediaOrSRT.deletingPathExtension()
        return base.appendingPathExtension(sidecarExtension)
    }

    static func load(near url: URL?) -> MediaLanguageRecord? {
        guard let url else { return nil }
        let candidates = [
            sidecarURL(for: url),
            url.deletingLastPathComponent().appendingPathComponent(
                url.deletingPathExtension().lastPathComponent + ".\(sidecarExtension)"
            )
        ]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                  let record = try? JSONDecoder().decode(MediaLanguageRecord.self, from: data) else {
                continue
            }
            return record
        }
        return nil
    }

    static func save(_ record: MediaLanguageRecord, near mediaURL: URL) throws {
        let out = sidecarURL(for: mediaURL)
        let data = try JSONEncoder().encode(record)
        try data.write(to: out, options: .atomic)
    }
}

enum MediaLanguageDetection: Sendable {
    case whisper(MediaLanguageRecord)
    case srtText(String, confidence: Double?)
    case user(String)
    case fallback(String)

    var code: String {
        switch self {
        case let .whisper(record): record.language
        case let .srtText(code, _): code
        case let .user(code): code
        case let .fallback(code): code
        }
    }

    var label: String {
        switch self {
        case let .whisper(record):
            let conf = record.confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "?"
            return "\(record.language) — Whisper/audio (\(conf))"
        case let .srtText(code, confidence):
            let conf = confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "?"
            return "\(code) — phân tích SRT (\(conf))"
        case let .user(code):
            return "\(code) — chọn thủ công"
        case let .fallback(code):
            return "\(code) — mặc định"
        }
    }
}