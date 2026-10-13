import Foundation

/// Project annotations, independent of subtitle text/timing and dubbing clips.
struct TimelineMarker: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let seconds: Double
    var note: String

    init(id: UUID = UUID(), seconds: Double, note: String = "") {
        self.id = id
        self.seconds = seconds
        self.note = note
    }
}

enum TimelineMarkerPolicy {
    static func normalized(_ markers: [TimelineMarker]) -> [TimelineMarker] {
        var seen: Set<UUID> = []
        return markers.filter { $0.seconds.isFinite && $0.seconds >= 0 && seen.insert($0.id).inserted }
            .sorted { $0.seconds == $1.seconds ? $0.id.uuidString < $1.id.uuidString : $0.seconds < $1.seconds }
    }

    static func create(at seconds: Double, duration: Double, existing: [TimelineMarker]) -> TimelineMarker? {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return nil }
        let time = min(duration, max(0, seconds))
        // Pressing M again while paused targets the existing marker for a note.
        return existing.first { abs($0.seconds - time) <= 0.02 } ?? TimelineMarker(seconds: time)
    }
}
