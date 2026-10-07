@preconcurrency import AVFoundation
import Foundation

enum NativeAudioPreparation {
    static func extract(media: URL, output: URL, range: CMTimeRange? = nil) async throws {
        let asset = AVURLAsset(url: media)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw OfflineWhisperError.noAudio
        }
        let work = Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            if let range { reader.timeRange = range }
            let settings: [String:Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let source = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            source.alwaysCopiesSampleData = false
            guard reader.canAdd(source) else { throw OfflineWhisperError.cannotPrepareAudio }
            reader.add(source)
            var file: AVAudioFile? = try AVAudioFile(forWriting: output, settings: settings,
                                                    commonFormat: .pcmFormatInt16, interleaved: true)
            guard reader.startReading() else { throw reader.error ?? OfflineWhisperError.cannotPrepareAudio }
            defer { reader.cancelReading(); file = nil }
            var count: Int64 = 0
            while let sample = source.copyNextSampleBuffer() {
                try Task.checkCancellation()
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file!.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
                      let channel = buffer.int16ChannelData else { throw OfflineWhisperError.cannotPrepareAudio }
                buffer.frameLength = AVAudioFrameCount(frames)
                guard CMBlockBufferGetDataLength(block) == frames * 2,
                      CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * 2, destination: channel[0]) == noErr else {
                    throw OfflineWhisperError.cannotPrepareAudio
                }
                try file!.write(from: buffer)
                count += Int64(frames)
            }
            guard reader.status == .completed, count > 0 else {
                throw reader.error ?? OfflineWhisperError.cannotPrepareAudio
            }
            file = nil
            let verified = try AVAudioFile(forReading: output)
            guard verified.length == count else { throw OfflineWhisperError.cannotPrepareAudio }
        }
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}
