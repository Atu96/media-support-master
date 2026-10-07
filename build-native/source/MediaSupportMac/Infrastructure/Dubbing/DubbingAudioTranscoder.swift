import AVFoundation
import Foundation

enum DubbingAudioTranscoder {
    static func writeCloudAudio(_ data: Data, sourceExtension: String, to outputURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("msm-tts-\(UUID().uuidString)")
                .appendingPathExtension(sourceExtension)
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            try data.write(to: sourceURL, options: .atomic)
            try? FileManager.default.removeItem(at: outputURL)

            // AVAudioFile buffers its container header. Close both files before
            // handing the URL to AVAudioPlayer or AVAsset, otherwise the first
            // immediate open can intermittently fail with GenericObjCError 0.
            let input = try AVAudioFile(forReading: sourceURL)
            let format = input.processingFormat
            let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            let capacity: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                input.close()
                output.close()
                throw DubbingError.invalidAudioBuffer
            }
            do {
                // AVAudioFile can throw Foundation._GenericObjCError 0 when a
                // read is attempted after the final frame. Bound every read by
                // the known remaining frame count instead of probing for EOF.
                while input.framePosition < input.length {
                    let remaining = input.length - input.framePosition
                    let requested = AVAudioFrameCount(min(Int64(capacity), remaining))
                    buffer.frameLength = 0
                    try input.read(into: buffer, frameCount: requested)
                    guard buffer.frameLength > 0 else { throw DubbingError.invalidAudioBuffer }
                    try output.write(from: buffer)
                }
                output.close()
                input.close()
            } catch {
                output.close()
                input.close()
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }

            let validation = try AVAudioFile(forReading: outputURL)
            let frames = validation.length
            validation.close()
            guard frames > 0 else {
                try? FileManager.default.removeItem(at: outputURL)
                throw DubbingError.invalidAudioBuffer
            }
        }.value
    }
}

@MainActor
enum DubbingPreviewAudioLoader {
    /// Reads the finalized file before creating AVAudioPlayer. Keeping the data
    /// alive avoids a second file-system handoff while playback is starting.
    static func prepare(from url: URL) throws -> (player: AVAudioPlayer, data: Data) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw DubbingError.invalidAudioBuffer }
        let player = try AVAudioPlayer(data: data)
        player.volume = 1
        guard player.prepareToPlay(), player.duration.isFinite, player.duration > 0 else {
            throw DubbingError.invalidAudioBuffer
        }
        return (player, data)
    }
}
