import AVFoundation
import Foundation

struct DubbingAudioMergeClip: Sendable {
    let audioURL: URL
    let startOffset: Double
    let playbackRate: Double
}

/// Builds one cached clip from existing cue audio. AVFoundation streams the
/// assets during export, so memory use does not grow with the project length.
enum DubbingAudioMergeService {
    static func merge(
        clips: [DubbingAudioMergeClip],
        outputURL: URL
    ) async throws -> Double {
        guard !clips.isEmpty else { throw DubbingError.missingRenderedClips }

        let composition = AVMutableComposition()
        var destinationTracks: [AVMutableCompositionTrack] = []
        var trackAvailableAt: [Double] = []
        var mergedDuration = 0.0

        for clip in clips.sorted(by: { $0.startOffset < $1.startOffset }) {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: clip.audioURL)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw DubbingError.missingAudioTrack(clip.audioURL)
            }
            let sourceDuration = try await asset.load(.duration).seconds
            guard sourceDuration.isFinite, sourceDuration > 0 else { continue }

            let rate = min(
                DubbingRenderedCue.maximumPlaybackRate,
                max(DubbingRenderedCue.minimumPlaybackRate, clip.playbackRate)
            )
            let start = max(0, clip.startOffset)
            let playedDuration = sourceDuration / rate
            guard playedDuration > 0.01 else { continue }

            let destinationIndex: Int
            if let reusable = trackAvailableAt.firstIndex(where: { $0 <= start + 0.001 }) {
                destinationIndex = reusable
            } else {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw DubbingError.cannotCreateComposition }
                destinationTracks.append(track)
                trackAvailableAt.append(0)
                destinationIndex = destinationTracks.count - 1
            }

            let insertionTime = CMTime(seconds: start, preferredTimescale: 600)
            let sourceTime = CMTime(seconds: sourceDuration, preferredTimescale: 600)
            let targetTime = CMTime(seconds: playedDuration, preferredTimescale: 600)
            let destinationTrack = destinationTracks[destinationIndex]
            try destinationTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceTime),
                of: sourceTrack,
                at: insertionTime
            )
            if abs(rate - 1) > 0.001 {
                destinationTrack.scaleTimeRange(
                    CMTimeRange(start: insertionTime, duration: sourceTime),
                    toDuration: targetTime
                )
            }
            trackAvailableAt[destinationIndex] = start + playedDuration
            mergedDuration = max(mergedDuration, start + playedDuration)
        }

        guard !destinationTracks.isEmpty, mergedDuration > 0 else {
            throw DubbingError.missingRenderedClips
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = destinationTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTimePitchAlgorithm = .timeDomain
            return parameters
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw DubbingError.cannotCreateComposition }
        exporter.audioMix = audioMix
        try await exporter.export(to: outputURL, as: .m4a)
        return mergedDuration
    }
}
