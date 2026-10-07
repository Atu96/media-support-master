import AppKit
import AVFoundation
import CoreText
import QuartzCore

private struct Failure: Error { let message: String }

@main @MainActor
enum SubtitleRendererTests {
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }

    static func main() async throws {
        var style = SubtitleBurnStyle()
        style.fontSize = 54
        style.fontName = "Helvetica"
        style.boxEnabled = false
        let samples = ["Tiếng Việt 100.000 tỷ", "日本語の字幕です", "中文逐字显示", "한국어 자막입니다", "office affinity", "العربية جميلة", "👨‍👩‍👧‍👦 🎵"]
        for text in samples {
            let layout = SubtitleTextLayout(text: text, style: style, fontSize: 54, size: CGSize(width: 1500, height: 100))
            try check(layout.image != nil && !layout.units.isEmpty, "missing shaped image: \(text)")
            let source = text as NSString
            for unit in layout.units {
                try check(unit.sourceIndex == source.rangeOfComposedCharacterSequence(at: unit.sourceIndex).location,
                          "split composed character: \(text)")
                try check(unit.rect.minX.isFinite && unit.rect.maxX < 1500, "invalid glyph geometry")
            }
            let steps = layout.revealSteps(text: text, transition: .leftToRight)
            try check(steps.count == layout.units.count, "missing glyph step")
        }
        print("✓ Native shaping: VI/JA/ZH/KO/Latin/Arabic/emoji")

        let multiline = "TOP LINE\nBOTTOM LINE"
        let layout = SubtitleTextLayout(text: multiline, style: style, fontSize: 54, size: CGSize(width: 1000, height: 160))
        let rtl = layout.revealSteps(text: multiline, transition: .rightToLeft)
        let firstTop = layout.units.filter { $0.line == 0 }.max { $0.rect.minX < $1.rect.minX }!
        try check(rtl.first!.first == firstTop.rect, "RTL started from bottom line")
        let cjk = "今天我们学习中文"
        let words = SubtitleTextLayout(text: cjk, style: style, fontSize: 54, size: CGSize(width: 1000, height: 100))
        try check(words.revealSteps(text: cjk, transition: .wordByWord).count > 1, "CJK treated as one whitespace word")
        print("✓ Native reveal: RTL top-to-bottom; CJK word segmentation")

        for transition in [SubtitleTextTransition.leftToRight, .rightToLeft, .wordByWord] {
            style.textTransition = transition
            let segment = SRTSegment(id: 1, index: 1, timing: "", startSeconds: 0.3, endSeconds: 2.7, text: multiline)
            let tree = SubtitleCueLayerRenderer.makeCueLayer(segment: segment, style: style,
                                                            renderSize: CGSize(width: 1920, height: 1080), decorationDensity: 4)
            let mask = tree.sublayers?.compactMap { $0.mask }.first
            let animation = mask?.animation(forKey: "shaped-type-on") as? CAKeyframeAnimation
            try check(animation?.calculationMode == .discrete, "continuous wipe instead of shaped Type On")
            try check((animation?.values?.count ?? 0) > 2, "missing reveal keyframes")
            let paths = animation!.values! as! [CGPath]
            try check(paths[paths.count - 1] == paths[paths.count - 2], "terminal glyph not held in final discrete interval")
            try check(tree.position.y < 400, "subtitle not bottom anchored")
        }
        print("✓ Shared native layer: discrete reveal + bottom placement")

        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let input = folder.appendingPathComponent("source.mov")
            if !FileManager.default.fileExists(atPath: input.path) { try await sourceVideo(input) }
            var referencePixels: Int?
            for (name, transition, effect) in [
                ("plain", SubtitleTextTransition.none, SubtitleVisualEffect.none),
                ("ltr-plain", .leftToRight, .none),
                ("rtl-plain", .rightToLeft, .none),
                ("words-plain", .wordByWord, .none),
                ("ltr-golden", SubtitleTextTransition.leftToRight, SubtitleVisualEffect.goldenSweep),
                ("rtl-neon", .rightToLeft, .neonAura),
                ("words-stars", .wordByWord, .starlight),
                ("pop-butterfly", .softPop, .butterflyTrail),
                ("bottom-none", .bottomUp, .none)
            ] {
                style.textTransition = transition; style.visualEffect = effect
                style.effectColorHex = "#FFD66B"
                style.outlineEnabled = true; style.outlineWidth = 2
                style.shadowEnabled = true
                let output = folder.appendingPathComponent(name + ".mp4")
                let segments = [
                    SRTSegment(id: 1, index: 1, timing: "", startSeconds: 0.3, endSeconds: 2.7,
                               text: "Tiếng Việt 100.000 tỷ\n日本語の字幕 中文"),
                    SRTSegment(id: 2, index: 2, timing: "", startSeconds: 3, endSeconds: 5.5,
                               text: "office affinity العربية")
                ]
                try await SubtitleVideoExporter.export(videoURL: input, outputURL: output, segments: segments, style: style)
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                for (label, time) in [("before",0.1), ("early",0.43), ("middle",1.1), ("full",2.3), ("gap",2.85), ("second",4.3), ("after",5.8)] {
                    let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(name)-\(label).png"))
                    let pixels = brightPixels(image)
                    if label == "full" {
                        if name == "plain" { referencePixels = pixels }
                        if name.hasSuffix("-plain"), let referencePixels {
                            try check(abs(pixels - referencePixels) < max(15, referencePixels / 50),
                                      "completed reveal lost text: \(name) \(pixels) vs \(referencePixels)")
                        }
                    }
                    if ["before", "gap", "after"].contains(label) { try check(pixels == 0, "cue visible outside timing: \(name) \(label) \(pixels)") }
                    if ["full", "second"].contains(label) { try check(pixels > 150, "missing subtitle in export: \(name) \(label)") }
                }
                print("✓ Native video/frame smoke: \(name)")
            }
        }
    }

    static func brightPixels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: bytes.count, by: 4).filter { max(bytes[$0], bytes[$0+1], bytes[$0+2]) > 100 }.count
    }

    static func sourceVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 960, AVVideoHeightKey: 540
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 960, kCVPixelBufferHeightKey as String: 540
        ])
        writer.add(input)
        try check(writer.startWriting(), "source writer: \(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<180 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(nil, 960, 540, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard status == kCVReturnSuccess, let pixel = buffer else { throw Failure(message: "pixel buffer creation failed") }
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            try check(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)), "source frame failed")
        }
        input.markAsFinished()
        await writer.finishWriting()
        try check(writer.status == .completed, "source video failed")
    }
}
