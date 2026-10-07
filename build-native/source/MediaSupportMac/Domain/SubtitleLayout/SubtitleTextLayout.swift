import AppKit
import CoreText
import NaturalLanguage

extension SubtitleBurnStyle {
    static func nsColor(fromHex hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else { return .white }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Shape whole hard lines before deriving reveal units. Preserves kerning,
/// ligatures, fallback fonts and composed accents; no per-character SwiftUI Text.
struct SubtitleTextLayout {
    struct Unit {
        let line: Int
        let rect: CGRect
        let sourceIndex: Int
    }
    let image: CGImage?
    let units: [Unit]

    init(text: String, style: SubtitleBurnStyle, fontSize: CGFloat, size: CGSize) {
        let font = NSFont(name: style.fontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: SubtitleBurnStyle.nsColor(fromHex: style.textColorHex)
        ]
        if style.outlineEnabled && style.outlineWidth > 0 {
            attributes[.strokeColor] = SubtitleBurnStyle.nsColor(fromHex: style.outlineColorHex)
                .withAlphaComponent(style.outlineOpacity)
            attributes[.strokeWidth] = -CGFloat(style.outlineWidth) * 100 / max(CGFloat(style.fontSize), 1)
        }
        let pixelScale: CGFloat = 2
        let context = CGContext(data: nil, width: max(1, Int(ceil(size.width * pixelScale))),
                                height: max(1, Int(ceil(size.height * pixelScale))),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.scaleBy(x: pixelScale, y: pixelScale)
        var result: [Unit] = []
        var sourceOffset = 0
        for (lineIndex, string) in text.components(separatedBy: "\n").enumerated() {
            let attributed = NSAttributedString(string: string, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributed)
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let origin = CGPoint(x: (size.width - lineWidth) / 2,
                                 y: size.height - fontSize * 1.06 - CGFloat(lineIndex) * fontSize * 1.34)
            if let context {
                context.textPosition = origin
                CTLineDraw(line, context)
            }
            let source = string as NSString
            var clusters: [Int: CGRect] = [:]
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetStringIndices(run, CFRange(), &indices)
                CTRunGetAdvances(run, CFRange(), &advances)
                let runAttributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = runAttributes[kCTFontAttributeName] as! CTFont
                var bounds = [CGRect](repeating: .zero, count: count)
                CTFontGetBoundingRectsForGlyphs(runFont, .default, glyphs, &bounds, count)
                for index in 0..<count where indices[index] >= 0 && indices[index] < source.length {
                    let cluster = source.rangeOfComposedCharacterSequence(at: indices[index]).location
                    let ink = bounds[index].offsetBy(dx: origin.x + positions[index].x,
                                                     dy: origin.y + positions[index].y)
                    let advance = CGRect(x: origin.x + positions[index].x, y: origin.y - fontSize * 0.3,
                                         width: max(0, advances[index].width), height: fontSize * 1.34)
                    let rect = ink.union(advance)
                    clusters[cluster] = clusters[cluster].map { $0.union(rect) } ?? rect
                }
            }
            for (index, rect) in clusters {
                result.append(Unit(line: lineIndex, rect: rect, sourceIndex: sourceOffset + index))
            }
            sourceOffset += source.length + 1
        }
        image = context?.makeImage()
        units = result.sorted { $0.line == $1.line ? $0.rect.minX < $1.rect.minX : $0.line < $1.line }
    }

    func revealSteps(text: String, transition: SubtitleTextTransition) -> [[CGRect]] {
        var ordered = units
        if transition == .rightToLeft {
            ordered.sort { $0.line == $1.line ? $0.rect.minX > $1.rect.minX : $0.line < $1.line }
        }
        if transition == .wordByWord {
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            var words: [NSRange] = []
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                words.append(NSRange(range, in: text)); return true
            }
            var steps: [[CGRect]] = []
            var previous: String?
            for unit in ordered {
                let word = words.firstIndex { NSLocationInRange(unit.sourceIndex, $0) }
                let key = "\(unit.line):\(word ?? -1)"
                if key == previous { steps[steps.count - 1].append(unit.rect) }
                else { steps.append([unit.rect]); previous = key }
            }
            return steps
        }
        return ordered.map { [$0.rect] }
    }
}
