import AVFoundation
import Foundation

/// Small metadata-only cache. Hard-linked aliases share one asset duration lookup.
actor DubbingAudioDurationCache {
    static let shared = DubbingAudioDurationCache()

    private struct Key: Hashable {
        let device: UInt64
        let inode: UInt64
        let bytes: UInt64
        let modified: Date
    }

    private var values: [Key: Double] = [:]
    private var order: [Key] = []
    private var inFlight: [Key: Task<Double, Never>] = [:]
    private let capacity = 512

    func duration(at url: URL) async -> Double {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber,
              let bytes = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return 0 }
        let key = Key(device: device.uint64Value, inode: inode.uint64Value, bytes: bytes.uint64Value, modified: modified)
        if let value = values[key] { return value }
        if let task = inFlight[key] { return await task.value }
        let task = Task {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { return 0.0 }
            let seconds = duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : 0
        }
        inFlight[key] = task
        let duration = await task.value
        inFlight.removeValue(forKey: key)
        // Failed probes can be retried; finalized good files are cached by identity/version.
        if duration > 0 {
            values[key] = duration
            order.append(key)
            if order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
        }
        return duration
    }
}
