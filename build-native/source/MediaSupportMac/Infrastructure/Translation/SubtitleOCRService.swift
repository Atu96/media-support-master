import AVFoundation
import CryptoKit
import Foundation
import NaturalLanguage
import Vision

struct SubtitleOCRResult: Sendable {
    let segments: [SRTSegment]
    let language: String
    let sampledFrames: Int
    let recognitionRequests: Int
    let frameSeconds: Double
    let recognitionSeconds: Double
    let firstRecognitionSeconds: Double
}

enum SubtitleOCRError: LocalizedError {
    case noVideo
    case noText
    case invalidFrame
    var errorDescription: String? {
        switch self {
        case .noVideo: L10n.string("OCR cần video có hình ảnh.")
        case .noText: L10n.string("Không tìm thấy phụ đề trong vùng đã chọn. Hãy chọn lại vùng chữ.")
        case .invalidFrame: L10n.string("Không đọc được khung hình để lấy phụ đề.")
        }
    }
}

private final class OCRCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var generator: AVAssetImageGenerator?
    private var request: VNRecognizeTextRequest?

    func install(generator: AVAssetImageGenerator, request: VNRecognizeTextRequest? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.generator = generator
        self.request = request
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let generator = generator
        let request = request
        lock.unlock()
        generator?.cancelAllCGImageGeneration()
        request?.cancel()
    }
}

enum SubtitleOCRService {
    static func previewImage(media: URL, time: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        let cancellation = OCRCancellation()
        try cancellation.install(generator: generator)
        return try await withTaskCancellationHandler {
            let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            try Task.checkCancellation()
            return frame.image
        } onCancel: { cancellation.cancel() }
    }

    /// One worker and one image at a time. No ASR, network request or additional model download.
    static func scan(
        media: URL,
        region: SubtitleOCRRegion,
        interval: Double = 0.5,
        progress: @escaping @Sendable (Double, Int) async -> Void
    ) async throws -> SubtitleOCRResult {
        let cancellation = OCRCancellation()
        let worker = Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: media)
            guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw SubtitleOCRError.noVideo }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw SubtitleOCRError.noVideo }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            let supported = try request.supportedRecognitionLanguages()
            // Keep automatic detection focused on the app's five primary languages.
            // Use the actual runtime locale (Vision returns vi-VT on this OS).
            let primary = Set(["vi", "en", "ja", "ko", "zh"])
            request.recognitionLanguages = supported.filter {
                primary.contains(String($0.split(separator: "-").first ?? ""))
            }
            if request.recognitionLanguages.isEmpty { request.recognitionLanguages = supported }
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.015
            try cancellation.install(generator: generator, request: request)
            let step = min(1, max(0.25, interval))
            var accumulator = OCRSubtitleAccumulator()
            var previousDigest: Data?
            var previousText: String?
            var previousConfidence: Float = 0
            var frames = 0
            var recognitions = 0
            var frameSeconds = 0.0
            var recognitionSeconds = 0.0
            var firstRecognitionSeconds = 0.0
            var time = 0.0
            var lastPercent = -1
            while time < duration {
                try Task.checkCancellation()
                let frameStart = Date()
                let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                frameSeconds += Date().timeIntervalSince(frameStart)
                try Task.checkCancellation()
                let sample: OCRSubtitleSample = try autoreleasepool {
                    let image = frame.image
                    let selected = region.rect
                    let pixels = CGRect(x: selected.minX * Double(image.width), y: selected.minY * Double(image.height),
                                        width: selected.width * Double(image.width), height: selected.height * Double(image.height)).integral
                        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    guard let cropped = image.cropping(to: pixels) else { throw SubtitleOCRError.invalidFrame }
                    let digest = try pixelDigest(cropped)
                    if digest != previousDigest {
                        let recognitionStart = Date()
                        try VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
                        let elapsed = Date().timeIntervalSince(recognitionStart)
                        recognitionSeconds += elapsed
                        if recognitions == 0 { firstRecognitionSeconds = elapsed }
                        try Task.checkCancellation()
                        let observations = request.results ?? []
                        let recognized = observations.compactMap { observation -> (CGRect, String, Float)? in
                            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.45 else { return nil }
                            return (observation.boundingBox, candidate.string, candidate.confidence)
                        }.sorted {
                            if abs($0.0.midY - $1.0.midY) > min($0.0.height, $1.0.height) * 0.5 {
                                return $0.0.midY > $1.0.midY
                            }
                            return $0.0.minX < $1.0.minX
                        }
                        previousText = recognized.isEmpty && !observations.isEmpty ? nil : recognized.map { $0.1 }.joined(separator: "\n")
                        previousConfidence = recognized.map { $0.2 }.min() ?? 1
                        previousDigest = digest
                        recognitions += 1
                    }
                    return .init(time: min(duration, max(time, frame.actualTime.seconds)),
                                 text: previousText, confidence: previousConfidence)
                }
                accumulator.consume(sample)
                frames += 1
                let percent = Int(min(95, ((time + step) / duration) * 95))
                if percent > lastPercent {
                    lastPercent = percent
                    await progress(Double(percent) / 100, accumulator.segments.count)
                }
                time += step
            }
            try Task.checkCancellation()
            let segments = accumulator.finish(duration: duration)
            guard !segments.isEmpty else { throw SubtitleOCRError.noText }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(segments.map(\.text).joined(separator: " ").prefix(16_000)))
            let language = recognizer.dominantLanguage?.rawValue.split(separator: "-").first.map(String.init) ?? "auto"
            await progress(0.97, segments.count)
            return SubtitleOCRResult(segments: segments, language: language,
                                     sampledFrames: frames, recognitionRequests: recognitions,
                                     frameSeconds: frameSeconds, recognitionSeconds: recognitionSeconds,
                                     firstRecognitionSeconds: firstRecognitionSeconds)
        }
        return try await withTaskCancellationHandler {
            do { return try await worker.value }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            worker.cancel()
            cancellation.cancel()
        }
    }

    static func pixelDigest(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw SubtitleOCRError.invalidFrame }
        var hash = SHA256()
        bytes.withUnsafeBytes { hash.update(bufferPointer: $0) }
        return Data(hash.finalize())
    }
}
