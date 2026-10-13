import Foundation

extension SubtitleViewModel {
    @discardableResult
    func addTimelineMarker(at seconds: Double, duration: Double) -> TimelineMarker? {
        guard let media = mediaURL,
              let marker = TimelineMarkerPolicy.create(at: seconds, duration: duration, existing: timelineMarkers) else { return nil }
        if timelineMarkers.contains(where: { $0.id == marker.id }) { return marker }
        var updated = timelineMarkers
        updated.append(marker)
        return commitTimelineMarkers(updated, media: media) ? marker : nil
    }

    func updateTimelineMarker(_ id: UUID, note: String) -> Bool {
        guard let media = mediaURL, let index = timelineMarkers.firstIndex(where: { $0.id == id }) else { return false }
        var updated = timelineMarkers
        updated[index].note = note
        return commitTimelineMarkers(updated, media: media)
    }

    func removeTimelineMarker(_ id: UUID) -> Bool {
        guard let media = mediaURL, timelineMarkers.contains(where: { $0.id == id }) else { return false }
        return commitTimelineMarkers(timelineMarkers.filter { $0.id != id }, media: media)
    }

    private func commitTimelineMarkers(_ markers: [TimelineMarker], media: URL) -> Bool {
        do {
            let normalized = TimelineMarkerPolicy.normalized(markers)
            try ProjectBackupStore.saveMarkers(normalized, for: media)
            guard mediaURL == media else { return false }
            timelineMarkers = normalized
            return true
        } catch { exportMessage = error.localizedDescription; return false }
    }
}
