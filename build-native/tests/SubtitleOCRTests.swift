import AVFoundation
import CoreText
import Foundation

@main
enum SubtitleOCRTests {
    static func check(_ valid: Bool, _ message: String) throws {
        if !valid { throw NSError(domain: "OCRTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() async throws {
        try testColorDigest()
        let retained = CommandLine.arguments.dropFirst().first
        let root = retained.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("msm-ocr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { if retained == nil { try? FileManager.default.removeItem(at: root) } }
        let media = root.appendingPathComponent("subtitles.mp4")
        try await makeVideo(output: media, first: "Hello from Tokyo.", second: "Goodbye from Kyoto.", font: "Helvetica")
        let result = try await SubtitleOCRService.scan(media: media, region: .lower) { _, _ in }
        try check(result.segments.count == 2, "native OCR did not find two cues: \(result.segments.map(\.text))")
        try check(result.segments[0].text.contains("Tokyo") && result.segments[1].text.contains("Kyoto"), "wrong OCR text")
        try check(!result.segments.map(\.text).joined().contains("LOGO"), "crop included top text")
        try check(result.language == "en", "text language was not auto detected")
        try check(result.sampledFrames >= 8 && result.recognitionRequests <= result.sampledFrames, "unbounded recognition")
        print(String(format: "OCR_TIMING frames=%.3fs recognition=%.3fs first=%.3fs",
                     result.frameSeconds, result.recognitionSeconds, result.firstRecognitionSeconds))
        try check(abs(result.segments[0].startSeconds - 0.5) <= 0.3 && abs(result.segments[0].endSeconds - 2) <= 0.3,
                  "native OCR timestamps exceeded sample interval")
        try check(SRTDocument.parseSegments(SRTDocument.renderSRT(result.segments)).count == 2, "OCR SRT did not round-trip")
        let accurate = try await SubtitleOCRService.scan(media: media, region: .lower, interval: 0.25) { _, _ in }
        try check(accurate.segments.count == 2 && accurate.sampledFrames >= 16, "closer scanning failed")
        let multiline = root.appendingPathComponent("multiline.mp4")
        try await makeVideo(output: multiline, first: "Hello from Tokyo.\nNice to meet you.",
                            second: "Goodbye from Kyoto.\nSee you soon.", font: "Helvetica")
        let lines = try await SubtitleOCRService.scan(media: multiline, region: .lower) { _, _ in }
        try check(lines.segments.count == 2 && lines.segments[0].text.contains("\n")
                  && lines.segments[0].text.hasPrefix("Hello"), "two-line OCR order failed")
        let rotated = root.appendingPathComponent("rotated.mp4")
        try await makeVideo(output: rotated, first: "Hello from Tokyo.", second: "Goodbye from Kyoto.",
                            font: "Helvetica", rotated: true)
        let oriented = try await SubtitleOCRService.scan(media: rotated, region: .lower) { _, _ in }
        try check(oriented.segments.count == 2 && oriented.segments[0].text.contains("Tokyo"),
                  "displayed-image crop failed after preferred transform")
        for (code, text, font) in [
            ("vi", "Xin chào Việt Nam", "Helvetica"),
            ("ja", "東京で電車に乗ります。", "Hiragino Sans"),
            ("ko", "한국에서 여행을 시작합니다", "Apple SD Gothic Neo"),
            ("zh", "今天我们去北京旅行", "PingFang SC")
        ] {
            let file = root.appendingPathComponent("\(code).mp4")
            try await makeVideo(output: file, first: text, second: text, font: font)
            let scan = try await SubtitleOCRService.scan(media: file, region: .lower, interval: 1) { _, _ in }
            try check(!scan.segments.isEmpty, "automatic OCR failed for \(code)")
            try check(scan.language.hasPrefix(code), "language \(code) became \(scan.language): \(scan.segments.map(\.text))")
        }
        let task = Task {
            try await SubtitleOCRService.scan(media: media, region: .lower) { _, _ in
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do { _ = try await task.value; try check(false, "scan ignored cancellation") }
        catch is CancellationError { }
        do {
            _ = try await SubtitleOCRService.scan(media: media,
                region: .init(x: 0.5, y: 0.35, width: 0.3, height: 0.1)) { _, _ in }
            try check(false, "empty region manufactured subtitles")
        } catch SubtitleOCRError.noText { }
        print("✓ Native OCR: crop, automatic VI/EN/JA/KO/ZH, cue timing/SRT, blank and cancellation")
    }

    static func makeVideo(output: URL, first: String, second: String, font: String, rotated: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        if rotated { input.transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1280, ty: 720) }
        writer.add(input)
        try check(writer.startWriting(), "video writer failed")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<40 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var pixel: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
            let buffer = pixel!
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            if rotated {
                context.translateBy(x: 1280, y: 720)
                context.scaleBy(x: -1, y: -1)
            }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
            draw("TOP LOGO", font: "Helvetica", at: CGPoint(x: 100, y: 620), context: context)
            if (5..<20).contains(index) { draw(first, font: font, at: CGPoint(x: 100, y: 55), context: context) }
            if (25..<39).contains(index) { draw(second, font: font, at: CGPoint(x: 100, y: 55), context: context) }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try check(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 10)), "frame append failed")
        }
        input.markAsFinished()
        await writer.finishWriting()
        try check(writer.status == .completed, "video finalize failed")
    }

    static func draw(_ text: String, font: String, at point: CGPoint, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let lines = text.split(separator: "\n")
        for (index, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(text), attributes: attributes))
            context.textPosition = CGPoint(x: point.x, y: point.y + Double(lines.count - index - 1) * 60)
            CTLineDraw(line, context)
        }
    }

    static func testColorDigest() throws {
        var byGray: [UInt8: CGImage] = [:]
        var testedCollision = false
        for channel in 0..<3 {
            for value in 1..<255 {
                let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                var rgb = [CGFloat](repeating: 0, count: 3)
                rgb[channel] = CGFloat(value) / 255
                context.setFillColor(CGColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
                let image = context.makeImage()!
                let gray = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                gray.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                let key = gray.data!.load(as: UInt8.self)
                if channel > 0, let previous = byGray[key] {
                    try check(try SubtitleOCRService.pixelDigest(previous) != SubtitleOCRService.pixelDigest(image),
                              "color-only text changes must invalidate cached recognition")
                    testedCollision = true
                    break
                }
                byGray[key] = image
            }
            if testedCollision { break }
        }
        try check(testedCollision, "color-cache fixture did not test equal-luminance images")
    }
}
