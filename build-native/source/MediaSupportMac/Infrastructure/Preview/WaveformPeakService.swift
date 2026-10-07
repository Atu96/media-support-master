import AVFoundation
import Foundation

/// Đọc audio thành peak 0...1 ở nền. Kết quả chỉ là số thực nhẹ, không giữ sample audio trong RAM.
///
/// Hai rule quan trọng cho media dài:
/// - duration phải lấy bằng async AVFoundation load, không suy từ số PCM interleaved;
/// - mỗi peak map theo PTS/frame thật, nên AAC stereo/resample không thể làm timeline dài gấp đôi.
enum WaveformPeakService {
    struct Result: Sendable {
        let peaks: [Float]
        let duration: Double
        let silenceScores: [Float]

        var boundaryAudioEvidence: SpeechBoundaryAudioEvidence {
            SpeechBoundaryAudioEvidence(silenceScores: silenceScores, duration: duration)
        }
    }

    /// `targetBins == 0` chọn mật độ phù hợp duration thật. Đủ rõ ở zoom sâu nhưng
    /// không giữ PCM và không cần decode lại mỗi khi đổi zoom.
    static func loadPeaks(url: URL, targetBins: Int = 0) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let assetDuration = try await asset.load(.duration).seconds
        // Một số M4A AAC ghi timescale track bất thường: AVAsset duration có thể
        // thành 2×. AVAudioFile trả số PCM frame/rate thật; video không mở được
        // bằng AVAudioFile thì vẫn dùng asset duration bình thường.
        let duration = await Task.detached(priority: .utility) {
            canonicalAudioDuration(url: url) ?? assetDuration
        }.value
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }

        let requested = targetBins > 0 ? targetBins : Int((duration * 96).rounded(.up))
        let bins = min(180_000, max(12_000, requested))
        let cacheKey = cacheKey(for: url, bins: bins)
        if let cached = await WaveformPeakMemoryCache.shared.value(for: cacheKey) {
            return cached
        }

        // Waveform là tác vụ phân tích: để priority thấp hơn playback / kéo cue.
        let result = try await Task.detached(priority: .utility) {
            try decode(url: url, duration: duration, bins: bins)
        }.value
        await WaveformPeakMemoryCache.shared.insert(
            result,
            for: cacheKey,
            assetKey: assetCacheKey(for: url)
        )
        return result
    }

    /// Chỉ dùng kết quả waveform đã có. Chép lời không chờ và không decode lại
    /// toàn media chỉ để lấy bằng chứng phụ cho vài ranh giới cue.
    static func cachedAudioEvidence(url: URL) async -> SpeechBoundaryAudioEvidence? {
        await WaveformPeakMemoryCache.shared.latestValue(
            forAssetKey: assetCacheKey(for: url)
        )?.boundaryAudioEvidence
    }

    private static func decode(url: URL, duration: Double, bins: Int) throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        // AVFoundation cấp phát block riêng; không cần copy thêm vào Swift trước khi tính peak.
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CocoaError(.fileReadCorruptFile) }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        var peaks = [Float](repeating: 0, count: bins)
        var energySums = [Double](repeating: 0, count: bins)
        var energyCounts = [Int](repeating: 0, count: bins)
        var decodedFrames: Int64 = 0
        var expectedFrames: Int64?
        while reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  asbd.mSampleRate > 0 else { continue }

            var length = 0
            var rawPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &rawPointer
            )
            guard let rawPointer, length >= MemoryLayout<Int16>.size else { continue }

            let channels = max(1, Int(asbd.mChannelsPerFrame))
            let samplesPerFrame = max(channels, Int(asbd.mBytesPerFrame) / MemoryLayout<Int16>.size)
            let scalarCount = length / MemoryLayout<Int16>.size
            let frameCount = scalarCount / samplesPerFrame
            guard frameCount > 0 else { continue }

            // Đếm *frame* (không phải scalar interleaved). Nhờ vậy stereo không
            // kéo waveform dài gấp đôi; group theo bin để không làm Double divide
            // hàng chục triệu lần trên audio dài.
            let totalFrames = expectedFrames ?? max(1, Int64((duration * asbd.mSampleRate).rounded()))
            expectedFrames = totalFrames

            rawPointer.withMemoryRebound(to: Int16.self, capacity: scalarCount) { samples in
                var localFrame = 0
                while localFrame < frameCount {
                    let absoluteFrame = decodedFrames + Int64(localFrame)
                    let bin = min(bins - 1, max(0, Int((absoluteFrame * Int64(bins)) / totalFrames)))
                    let nextFrame = min(
                        Int64(frameCount),
                        max(Int64(localFrame + 1), ((Int64(bin + 1) * totalFrames + Int64(bins) - 1) / Int64(bins)) - decodedFrames)
                    )
                    var magnitude = 0
                    var energy = 0.0
                    var energyCount = 0
                    for frame in localFrame..<Int(nextFrame) {
                        let start = frame * samplesPerFrame
                        for channel in 0..<channels where start + channel < scalarCount {
                            let value = Int(samples[start + channel])
                            magnitude = max(magnitude, value == Int(Int16.min) ? 32_768 : abs(value))
                            let normalized = Double(value) / 32_768
                            energy += normalized * normalized
                            energyCount += 1
                        }
                    }
                    peaks[bin] = max(peaks[bin], Float(magnitude) / 32_768)
                    energySums[bin] += energy
                    energyCounts[bin] += energyCount
                    localFrame = Int(nextFrame)
                }
            }
            decodedFrames += Int64(frameCount)
        }
        guard reader.status != .failed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        let scale = 1 / max(0.000_1, peaks.max() ?? 1)
        let normalized = peaks.map { pow(min(1, $0 * scale), 0.65) }
        let rms = zip(energySums, energyCounts).map { sum, count in
            count > 0 ? Float(sqrt(sum / Double(count))) : 0
        }
        let sortedRMS = rms.sorted()
        func percentile(_ fraction: Double) -> Float {
            guard !sortedRMS.isEmpty else { return 0 }
            let index = min(
                sortedRMS.count - 1,
                max(0, Int((Double(sortedRMS.count - 1) * fraction).rounded()))
            )
            return sortedRMS[index]
        }
        let noiseFloor = percentile(0.12)
        let speechReference = max(noiseFloor + 0.002, percentile(0.78))
        let energySpan = max(0.002, speechReference - noiseFloor)
        let silenceScores = rms.map { value in
            min(1, max(0, 1 - (value - noiseFloor) / energySpan))
        }
        return Result(peaks: normalized, duration: duration, silenceScores: silenceScores)
    }

    private static func cacheKey(for url: URL, bins: Int) -> String {
        "\(assetCacheKey(for: url))|\(bins)"
    }

    private static func assetCacheKey(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(modified)"
    }

    private static func canonicalAudioDuration(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        return duration.isFinite && duration > 0 ? duration : nil
    }
}

/// Cache process-local, tự invalid khi file đổi size/date. Không ghi media/PCM vào ổ.
private actor WaveformPeakMemoryCache {
    static let shared = WaveformPeakMemoryCache()
    private var order: [String] = []
    private var values: [String: WaveformPeakService.Result] = [:]
    private var latestByAssetKey: [String: WaveformPeakService.Result] = [:]
    private var assetKeyByCacheKey: [String: String] = [:]
    private var latestCacheKeyByAssetKey: [String: String] = [:]
    private let limit = 3

    func value(for key: String) -> WaveformPeakService.Result? {
        guard let result = values[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return result
    }

    func latestValue(forAssetKey key: String) -> WaveformPeakService.Result? {
        latestByAssetKey[key]
    }

    func insert(
        _ result: WaveformPeakService.Result,
        for key: String,
        assetKey: String
    ) {
        values[key] = result
        latestByAssetKey[assetKey] = result
        assetKeyByCacheKey[key] = assetKey
        latestCacheKeyByAssetKey[assetKey] = key
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > limit {
            let evictedKey = order.removeFirst()
            values.removeValue(forKey: evictedKey)
            if let assetKey = assetKeyByCacheKey.removeValue(forKey: evictedKey),
               latestCacheKeyByAssetKey[assetKey] == evictedKey {
                latestCacheKeyByAssetKey.removeValue(forKey: assetKey)
                latestByAssetKey.removeValue(forKey: assetKey)
            }
        }
    }
}
