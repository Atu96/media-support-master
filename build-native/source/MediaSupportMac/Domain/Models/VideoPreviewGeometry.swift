import AVFoundation
import CoreGraphics
import Foundation

/// Hình học preview dùng chung cho phụ đề, độc lập với mọi workflow chỉnh/cắt video.
enum VideoPreviewFrame: Equatable {
    case landscape16x9
    case portrait9x16
    case square1x1

    var aspectRatio: CGFloat {
        switch self {
        case .landscape16x9: 16 / 9
        case .portrait9x16: 9 / 16
        case .square1x1: 1
        }
    }

    var referencePixelSize: CGSize {
        switch self {
        case .landscape16x9: CGSize(width: 1920, height: 1080)
        case .portrait9x16: CGSize(width: 1080, height: 1920)
        case .square1x1: CGSize(width: 1080, height: 1080)
        }
    }

    static func classify(displaySize: CGSize) -> VideoPreviewFrame {
        let width = max(1, abs(displaySize.width))
        let height = max(1, abs(displaySize.height))
        let ratio = width / height
        if ratio >= 1.12 { return .landscape16x9 }
        if ratio <= 0.88 { return .portrait9x16 }
        return .square1x1
    }
}

enum VideoGeometryProbe {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var values: [URL: CGSize] = [:]
    }

    private static let cache = Cache()

    static func displaySize(for url: URL) -> CGSize {
        cache.lock.lock()
        if let cached = cache.values[url] {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()

        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return CGSize(width: 1920, height: 1080)
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        cache.lock.lock()
        cache.values[url] = size
        cache.lock.unlock()
        return size
    }
}
