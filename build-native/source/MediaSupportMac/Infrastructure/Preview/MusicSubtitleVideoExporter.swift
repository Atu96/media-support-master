import AppKit
import AVFoundation
import CoreText
import QuartzCore

enum SubtitleVideoExportError: LocalizedError {
    case missingVideoTrack
    case cannotCreateExporter
    case unsupportedOutput

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack: "Video không có track hình ảnh để xuất."
        case .cannotCreateExporter: "Không thể khởi tạo bộ dựng video hiệu ứng."
        case .unsupportedOutput: "Định dạng video đầu ra chưa được hỗ trợ."
        }
    }
}

/// Bộ dựng video phụ đề native dùng chung. Hiệu ứng nhạc là app-only và không tham gia FCPXML.
@MainActor
enum SubtitleVideoExporter {
    static func export(
        videoURL: URL,
        outputURL: URL,
        segments: [SRTSegment],
        style: SubtitleBurnStyle
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SubtitleVideoExportError.missingVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        let fps = Int32(style.fps) ?? 30
        composition.frameDuration = CMTime(value: 1, timescale: max(1, fps))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let videoInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        videoInstruction.setTransform(normalizedTransform, at: .zero)
        instruction.layerInstructions = [videoInstruction]
        composition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.masksToBounds = true
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let decorationBudget = max(2, min(style.effectDensity, 720 / max(1, segments.count)))
        for segment in segments where segment.durationSeconds > 0.04 && !segment.text.isEmpty {
            let cueLayer = SubtitleCueLayerRenderer.makeCueLayer(
                segment: segment,
                style: style,
                renderSize: renderSize,
                decorationDensity: decorationBudget
            )
            parentLayer.addSublayer(cueLayer)
        }
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw SubtitleVideoExportError.cannotCreateExporter
        }
        exporter.videoComposition = composition
        exporter.shouldOptimizeForNetworkUse = true

        let fileType: AVFileType
        if outputURL.pathExtension.lowercased() == "mp4", exporter.supportedFileTypes.contains(.mp4) {
            fileType = .mp4
        } else if exporter.supportedFileTypes.contains(.mov) {
            fileType = .mov
        } else if let first = exporter.supportedFileTypes.first {
            fileType = first
        } else {
            throw SubtitleVideoExportError.unsupportedOutput
        }
        try? FileManager.default.removeItem(at: outputURL)
        try await exporter.export(to: outputURL, as: fileType)
    }

}
