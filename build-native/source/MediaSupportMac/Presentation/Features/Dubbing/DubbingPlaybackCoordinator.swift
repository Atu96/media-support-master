import AVFoundation
import Foundation

/// Sở hữu toàn bộ AVPlayer tạm của DUB. Session model chỉ cung cấp clip và
/// mix state; coordinator này giữ seek token, drift correction và lifecycle.
@MainActor
final class DubbingPlaybackCoordinator {
    private final class SynchronizedVoicePlayback: @unchecked Sendable {
        let cueID: Int
        let fingerprint: String
        let rate: Double
        let player: AVPlayer
        var seekInFlight = false
        var token: UInt = 0
        var lastSeekAt: TimeInterval = 0

        init(cue: DubbingRenderedCue, player: AVPlayer) {
            cueID = cue.id
            fingerprint = cue.fingerprint
            rate = cue.playbackRate
            self.player = player
        }
    }

    private var auditionPlayer: AVPlayer?
    private var auditionStopTask: Task<Void, Never>?
    private var synchronizedPlayers: [Int: SynchronizedVoicePlayback] = [:]

    func audition(_ cue: DubbingRenderedCue) {
        stopAudition()
        let item = AVPlayerItem(url: cue.audioURL)
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        auditionPlayer = player
        player.playImmediately(atRate: Float(cue.playbackRate))
        auditionStopTask = Task { [weak self, weak player] in
            try? await Task.sleep(for: .seconds(cue.playedDuration))
            guard !Task.isCancelled else { return }
            player?.pause()
            if self?.auditionPlayer === player { self?.auditionPlayer = nil }
        }
    }

    func synchronize(
        cues: [DubbingRenderedCue],
        mediaTime: Double,
        isPlaying: Bool,
        originalVolume: Float,
        dubVolume: Float,
        duckOriginal: Bool
    ) {
        let mediaPreview = AVPreviewService.shared
        guard isPlaying, mediaPreview.isLoaded, mediaPreview.player != nil else {
            stopSynchronized(restoreOriginalVolume: originalVolume)
            return
        }

        stopAudition()
        let activeCues = cues.filter {
            mediaTime >= $0.startSeconds && mediaTime < $0.startSeconds + $0.playedDuration
        }
        guard !activeCues.isEmpty else {
            stopSynchronized(restoreOriginalVolume: originalVolume)
            return
        }

        mediaPreview.player?.volume = duckOriginal ? min(originalVolume, 0.18) : originalVolume
        let activeIDs = Set(activeCues.map(\.id))
        for cueID in synchronizedPlayers.keys.filter({ !activeIDs.contains($0) }) {
            removeSynchronized(cueID: cueID)
        }

        for cue in activeCues {
            if let current = synchronizedPlayers[cue.id],
               current.fingerprint == cue.fingerprint,
               abs(current.rate - cue.playbackRate) <= 0.001 {
                synchronize(current, cue: cue, mediaTime: mediaTime, dubVolume: dubVolume)
            } else {
                removeSynchronized(cueID: cue.id)
                startSynchronized(cue: cue, mediaTime: mediaTime, dubVolume: dubVolume)
            }
        }
    }

    func stopAll(restoreOriginalVolume: Float) {
        stopAudition()
        stopSynchronized(restoreOriginalVolume: restoreOriginalVolume)
    }

    private func stopAudition() {
        auditionStopTask?.cancel()
        auditionStopTask = nil
        auditionPlayer?.pause()
        auditionPlayer = nil
    }

    private func startSynchronized(cue: DubbingRenderedCue, mediaTime: Double, dubVolume: Float) {
        let item = AVPlayerItem(url: cue.audioURL)
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = dubVolume
        let playback = SynchronizedVoicePlayback(cue: cue, player: player)
        synchronizedPlayers[cue.id] = playback
        seek(
            playback,
            cue: cue,
            audioTime: DubbingPlaybackMath.expectedAudioTime(for: cue, mediaTime: mediaTime)
        )
    }

    private func seek(
        _ playback: SynchronizedVoicePlayback,
        cue: DubbingRenderedCue,
        audioTime: Double
    ) {
        playback.token &+= 1
        let token = playback.token
        playback.seekInFlight = true
        playback.lastSeekAt = ProcessInfo.processInfo.systemUptime
        let target = CMTime(seconds: audioTime, preferredTimescale: 600)
        playback.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak playback] finished in
            Task { @MainActor in
                guard let self, let playback, token == playback.token else { return }
                playback.seekInFlight = false
                guard finished,
                      self.synchronizedPlayers[cue.id] === playback,
                      AVPreviewService.shared.isPlaying,
                      abs(playback.rate - cue.playbackRate) <= 0.001 else { return }
                playback.player.playImmediately(atRate: Float(cue.playbackRate))
            }
        }
    }

    private func synchronize(
        _ playback: SynchronizedVoicePlayback,
        cue: DubbingRenderedCue,
        mediaTime: Double,
        dubVolume: Float
    ) {
        playback.player.volume = dubVolume
        guard !playback.seekInFlight else { return }
        let expected = DubbingPlaybackMath.expectedAudioTime(for: cue, mediaTime: mediaTime)
        let actual = playback.player.currentTime().seconds
        let now = ProcessInfo.processInfo.systemUptime
        if DubbingPlaybackMath.shouldCorrectDrift(
            actualAudioTime: actual,
            expectedAudioTime: expected,
            secondsSinceLastSeek: now - playback.lastSeekAt
        ) {
            seek(playback, cue: cue, audioTime: expected)
        } else if playback.player.rate == 0 {
            playback.player.playImmediately(atRate: Float(cue.playbackRate))
        }
    }

    private func stopSynchronized(restoreOriginalVolume: Float) {
        for playback in synchronizedPlayers.values {
            playback.token &+= 1
            playback.player.pause()
        }
        synchronizedPlayers.removeAll()
        AVPreviewService.shared.player?.volume = restoreOriginalVolume
    }

    private func removeSynchronized(cueID: Int) {
        guard let playback = synchronizedPlayers.removeValue(forKey: cueID) else { return }
        playback.token &+= 1
        playback.player.pause()
    }
}
