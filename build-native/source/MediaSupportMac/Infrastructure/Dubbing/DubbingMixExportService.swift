import AVFoundation
import Foundation

enum DubbingMixExportService {
    static func export(
        mediaURL: URL,
        renderedCues: [DubbingRenderedCue],
        settings: DubbingMixSettings,
        outputURL: URL
    ) async throws {
        guard !renderedCues.isEmpty else { throw DubbingError.missingRenderedClips }

        let sourceAsset = AVURLAsset(url: mediaURL)
        let sourceDuration = try await sourceAsset.load(.duration)
        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: sourceDuration)

        if let sourceVideo = try await sourceAsset.loadTracks(withMediaType: .video).first {
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw DubbingError.cannotCreateComposition }
            try videoTrack.insertTimeRange(fullRange, of: sourceVideo, at: .zero)
            videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        }

        var originalCompositionTrack: AVMutableCompositionTrack?
        if let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).first {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw DubbingError.cannotCreateComposition }
            try audioTrack.insertTimeRange(fullRange, of: sourceAudio, at: .zero)
            originalCompositionTrack = audioTrack
        }

        var dubTracks: [AVMutableCompositionTrack] = []
        var trackAvailableAt: [Double] = []
        var insertedCues: [DubbingRenderedCue] = []
        for cue in renderedCues.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let clipAsset = AVURLAsset(url: cue.audioURL)
            guard let clipTrack = try await clipAsset.loadTracks(withMediaType: .audio).first else {
                throw DubbingError.missingAudioTrack(cue.audioURL)
            }
            let clipDuration = try await clipAsset.load(.duration)
            guard clipDuration.seconds.isFinite, clipDuration.seconds > 0 else { continue }
            let remainingMediaDuration = max(0, sourceDuration.seconds - cue.startSeconds)
            let playedDuration = min(cue.playedDuration, remainingMediaDuration)
            guard playedDuration > 0.01 else { continue }
            let sourceClipDuration = min(clipDuration.seconds, playedDuration * cue.playbackRate)
            let insertedSourceDuration = CMTime(seconds: sourceClipDuration, preferredTimescale: 600)
            let targetDuration = CMTime(seconds: playedDuration, preferredTimescale: 600)
            let insertionTime = CMTime(seconds: cue.startSeconds, preferredTimescale: 600)

            let trackIndex: Int
            if let reusable = trackAvailableAt.firstIndex(where: { $0 <= cue.startSeconds + 0.001 }) {
                trackIndex = reusable
            } else {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw DubbingError.cannotCreateComposition }
                dubTracks.append(track)
                trackAvailableAt.append(0)
                trackIndex = dubTracks.count - 1
            }
            let dubTrack = dubTracks[trackIndex]
            try dubTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertedSourceDuration),
                of: clipTrack,
                at: insertionTime
            )
            if abs(sourceClipDuration - playedDuration) > 0.001 {
                dubTrack.scaleTimeRange(
                    CMTimeRange(start: insertionTime, duration: insertedSourceDuration),
                    toDuration: targetDuration
                )
            }
            trackAvailableAt[trackIndex] = cue.startSeconds + playedDuration
            insertedCues.append(cue)
        }
        guard !insertedCues.isEmpty else { throw DubbingError.missingRenderedClips }

        let audioMix = AVMutableAudioMix()
        var parameters: [AVAudioMixInputParameters] = []

        if let originalCompositionTrack {
            let original = AVMutableAudioMixInputParameters(track: originalCompositionTrack)
            original.setVolume(settings.originalVolume, at: .zero)
            if settings.duckOriginal {
                applyDucking(
                    to: original,
                    cues: insertedCues,
                    baseVolume: settings.originalVolume,
                    duckedVolume: min(settings.originalVolume, settings.duckedOriginalVolume),
                    fadeDuration: settings.fadeDuration,
                    sourceDuration: sourceDuration.seconds
                )
            }
            parameters.append(original)
        }

        for dubTrack in dubTracks {
            let dub = AVMutableAudioMixInputParameters(track: dubTrack)
            dub.audioTimePitchAlgorithm = .timeDomain
            dub.setVolume(settings.dubVolume, at: .zero)
            parameters.append(dub)
        }
        audioMix.inputParameters = parameters

        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw DubbingError.cannotCreateComposition
        }
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mov)
    }

    private static func applyDucking(
        to parameters: AVMutableAudioMixInputParameters,
        cues: [DubbingRenderedCue],
        baseVolume: Float,
        duckedVolume: Float,
        fadeDuration: Double,
        sourceDuration: Double
    ) {
        let timescale: CMTimeScale = 600
        let fade = max(0.02, fadeDuration)
        let intervals = mergedVoiceIntervals(
            cues: cues,
            sourceDuration: sourceDuration,
            joiningGap: fade * 2
        )
        for interval in intervals {
            let start = interval.start
            let end = interval.end
            guard end > start else { continue }
            let fadeStart = max(0, start - fade)
            let fadeEnd = min(sourceDuration, end + fade)
            parameters.setVolumeRamp(
                fromStartVolume: baseVolume,
                toEndVolume: duckedVolume,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: fadeStart, preferredTimescale: timescale),
                    end: CMTime(seconds: start, preferredTimescale: timescale)
                )
            )
            parameters.setVolume(duckedVolume, at: CMTime(seconds: start, preferredTimescale: timescale))
            parameters.setVolumeRamp(
                fromStartVolume: duckedVolume,
                toEndVolume: baseVolume,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: end, preferredTimescale: timescale),
                    end: CMTime(seconds: fadeEnd, preferredTimescale: timescale)
                )
            )
        }
    }

    private static func mergedVoiceIntervals(
        cues: [DubbingRenderedCue],
        sourceDuration: Double,
        joiningGap: Double
    ) -> [(start: Double, end: Double)] {
        let intervals = cues.compactMap { cue -> (start: Double, end: Double)? in
            let start = max(0, cue.startSeconds)
            let end = min(sourceDuration, cue.startSeconds + cue.playedDuration)
            return end > start ? (start, end) : nil
        }.sorted { $0.start < $1.start }

        var merged: [(start: Double, end: Double)] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end + joiningGap {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
