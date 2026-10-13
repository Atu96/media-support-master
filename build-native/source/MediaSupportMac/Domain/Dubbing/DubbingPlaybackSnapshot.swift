import Foundation

/// Immutable effective timing, shared by lane/export/playback until an edit.
struct DubbingPlaybackSnapshot {
    let cues: [DubbingRenderedCue]
    private let prefixEnd: [Double]?

    init(cues: [DubbingRenderedCue]) {
        self.cues = cues
        var ends: [Double] = []
        var maximum = -Double.infinity
        var previous = -Double.infinity
        for cue in cues {
            let end = cue.startSeconds + cue.playedDuration
            guard cue.startSeconds.isFinite, end.isFinite, end >= cue.startSeconds,
                  cue.startSeconds >= previous else { prefixEnd = nil; return }
            previous = cue.startSeconds
            maximum = max(maximum, end)
            ends.append(maximum)
        }
        prefixEnd = ends
    }

    func activeCues(at time: Double) -> [DubbingRenderedCue] {
        func active(_ cue: DubbingRenderedCue) -> Bool {
            time >= cue.startSeconds && time < cue.startSeconds + cue.playedDuration
        }
        guard time.isFinite, let prefixEnd else { return cues.filter(active) }
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].startSeconds <= time { low = middle + 1 } else { high = middle }
        }
        let upper = low
        low = 0; high = upper
        while low < high {
            let middle = (low + high) / 2
            if prefixEnd[middle] <= time { low = middle + 1 } else { high = middle }
        }
        return cues[low..<upper].filter(active)
    }
}

final class DubbingPlaybackSnapshotCache {
    private var cached: DubbingPlaybackSnapshot?
    private(set) var rebuildCount = 0

    func invalidate() { cached = nil }

    func snapshot(rendered: [Int: DubbingRenderedCue], rates: [String: Double]) -> DubbingPlaybackSnapshot {
        if let cached { return cached }
        var cues: [DubbingRenderedCue] = rendered.values.map { cue in
            cue.applyingPlaybackRate(rates[cue.fingerprint])
        }
        cues.sort { left, right in
            if left.startSeconds == right.startSeconds { return left.id < right.id }
            return left.startSeconds < right.startSeconds
        }
        let snapshot = DubbingPlaybackSnapshot(cues: cues)
        cached = snapshot
        rebuildCount += 1
        return snapshot
    }
}
