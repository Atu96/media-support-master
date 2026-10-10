import Foundation

struct SubtitleOCRRegion: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Normalized displayed-image coordinates, origin at top left.
    static let lower = SubtitleOCRRegion(x: 0.05, y: 0.68, width: 0.9, height: 0.30)

    var rect: CGRect {
        let left = min(0.98, max(0, x))
        let top = min(0.98, max(0, y))
        return CGRect(x: left, y: top, width: min(1 - left, max(0.02, width)),
                      height: min(1 - top, max(0.02, height)))
    }

    static func selection(from start: CGPoint, to end: CGPoint, size: CGSize) -> SubtitleOCRRegion {
        guard size.width > 0, size.height > 0 else { return .lower }
        let a = CGPoint(x: min(size.width, max(0, start.x)), y: min(size.height, max(0, start.y)))
        let b = CGPoint(x: min(size.width, max(0, end.x)), y: min(size.height, max(0, end.y)))
        return .init(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                     width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)
    }
}

struct OCRSubtitleSample: Sendable {
    let time: Double
    /// nil = uncertain recognition; empty = an observed blank frame.
    let text: String?
    let confidence: Float
}

/// Streaming change detection with a single-sample jitter buffer, never stores frames.
struct OCRSubtitleAccumulator: Sendable {
    private struct Active: Sendable {
        var text: String
        var start: Double
        var last: Double
        var confidence: Float
        var count: Int
    }
    private var active: Active?
    private var pending: Active?
    private var lastTime = -1.0
    private(set) var segments: [SRTSegment] = []

    private func normalized(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .joined(separator: "\n").precomposedStringWithCanonicalMapping
    }

    mutating func consume(_ sample: OCRSubtitleSample) {
        guard sample.time.isFinite, sample.time >= 0, sample.time > lastTime else { return }
        let previousTime = max(0, lastTime)
        lastTime = sample.time
        guard let raw = sample.text else { return }
        let text = normalized(raw)
        if text.isEmpty {
            if let pending { transition(to: pending, boundary: pending.start) }
            self.pending = nil
            close(at: (previousTime + sample.time) / 2)
            return
        }
        guard sample.confidence >= 0.45 else { return }
        if active == nil {
            active = .init(text: text, start: (previousTime + sample.time) / 2,
                           last: sample.time, confidence: sample.confidence, count: 1)
            return
        }
        if var current = active, current.text == text {
            pending = nil
            current.last = sample.time
            current.count += 1
            current.confidence = max(current.confidence, sample.confidence)
            active = current
            return
        }
        if pending?.text == text, var confirmed = pending {
            confirmed.last = sample.time
            confirmed.count += 1
            confirmed.confidence = max(confirmed.confidence, sample.confidence)
            transition(to: confirmed, boundary: confirmed.start)
            pending = nil
        } else {
            if let pending { transition(to: pending, boundary: pending.start) }
            pending = .init(text: text, start: (previousTime + sample.time) / 2,
                            last: sample.time, confidence: sample.confidence, count: 1)
        }
    }

    mutating func finish(duration: Double) -> [SRTSegment] {
        if let pending { transition(to: pending, boundary: pending.start) }
        pending = nil
        close(at: max(0, duration))
        return segments
    }

    private mutating func transition(to next: Active, boundary: Double) {
        close(at: boundary)
        active = next
    }

    private mutating func close(at end: Double) {
        guard let item = active else { return }
        active = nil
        guard end - item.start >= 0.12, item.count >= 2 || item.confidence >= 0.8 else { return }
        let id = segments.count
        segments.append(.init(id: id, index: id + 1, timing: SRTTimecode.makeTiming(start: item.start, end: end),
                              startSeconds: item.start, endSeconds: end, text: item.text))
    }
}
