import AppKit
import AVFoundation
import CoreText
import QuartzCore

/// Shared native layer tree. Preview scrubs local time; export uses media time.
@MainActor
enum SubtitleCueLayerRenderer {
    static func makeCueLayer(
        segment: SRTSegment,
        style: SubtitleBurnStyle,
        renderSize: CGSize,
        decorationDensity: Int
    ) -> CALayer {
        let scale = renderSize.height / 1080
        let fontSize = CGFloat(style.fontSize) * scale
        let lineCount = max(1, segment.text.components(separatedBy: "\n").count)
        let horizontalPadding = 15 * scale
        let verticalPadding = 8 * scale
        let textWidth = renderSize.width * style.boxMaxWidthRatio - horizontalPadding * 2
        let textHeight = max(fontSize * 1.34 * CGFloat(lineCount), fontSize * 1.42)
        let containerSize = CGSize(
            width: renderSize.width * style.boxMaxWidthRatio,
            height: textHeight + verticalPadding * 2
        )
        let center = CGPoint(
            x: renderSize.width / 2,
            y: CGFloat(style.marginBottom) * scale + containerSize.height / 2
        )

        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: containerSize)
        container.position = center
        container.opacity = 0

        if style.boxEnabled {
            let background = CALayer()
            background.frame = container.bounds
            background.cornerRadius = CGFloat(style.boxCornerRadius) * scale
            background.backgroundColor = SubtitleBurnStyle.nsColor(fromHex: style.boxColorHex)
                .withAlphaComponent(style.boxOpacity).cgColor
            container.addSublayer(background)
        }

        let textFrame = CGRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: max(1, textWidth),
            height: textHeight
        )
        let textLayer = makeTextBitmapLayer(
            text: segment.text,
            style: style,
            fontSize: fontSize,
            frame: textFrame
        )
        if style.shadowEnabled {
            let radians = Double(style.shadowAngle) * .pi / 180
            let distance = CGFloat(style.shadowDistance) * scale
            textLayer.shadowColor = SubtitleBurnStyle.nsColor(fromHex: style.shadowColorHex)
                .withAlphaComponent(style.shadowOpacity).cgColor
            textLayer.shadowOpacity = 1
            textLayer.shadowRadius = CGFloat(style.shadowBlur) * scale
            textLayer.shadowOffset = CGSize(
                width: cos(radians) * distance,
                height: sin(radians) * distance
            )
        }
        let inkGroup = CALayer()
        inkGroup.frame = container.bounds
        container.addSublayer(inkGroup)
        if style.visualEffect == .neonAura {
            addNeonAura(to: inkGroup, textLayer: textLayer, segment: segment, style: style, scale: scale)
        }
        inkGroup.addSublayer(textLayer)

        if style.visualEffect == .goldenSweep {
            addLightSweep(
                to: inkGroup,
                text: segment.text,
                textFrame: textFrame,
                fontSize: fontSize,
                segment: segment,
                style: style
            )
        }
        if style.visualEffect == .starlight {
            addStarlight(
                to: container,
                segment: segment,
                style: style,
                density: decorationDensity,
                scale: scale
            )
        } else if style.visualEffect == .butterflyTrail {
            addButterflyTrail(
                to: container,
                segment: segment,
                style: style,
                density: decorationDensity,
                scale: scale
            )
        }
        if style.textTransition == .leftToRight
            || style.textTransition == .rightToLeft
            || style.textTransition == .wordByWord {
            addTextRevealMask(to: inkGroup, segment: segment, style: style,
                              textFrame: textFrame, fontSize: fontSize)
        }
        addCueAnimations(to: container, segment: segment, style: style, center: center, renderSize: renderSize)
        return container
    }

    private static func makeTextBitmapLayer(
        text: String,
        style: SubtitleBurnStyle,
        fontSize: CGFloat,
        frame: CGRect
    ) -> CALayer {
        let layout = SubtitleTextLayout(text: text, style: style, fontSize: fontSize, size: frame.size)
        let layer = CALayer()
        layer.frame = frame
        layer.contents = layout.image
        layer.contentsScale = 2
        return layer
    }

    private static func addCueAnimations(
        to layer: CALayer,
        segment: SRTSegment,
        style: SubtitleBurnStyle,
        center: CGPoint,
        renderSize: CGSize
    ) {
        let duration = max(0.08, segment.durationSeconds)
        let entranceDuration = style.transitionEntranceDuration(forCueDuration: duration)
        let enterKey = NSNumber(value: min(0.48, entranceDuration / duration))
        let begin = AVCoreAnimationBeginTimeAtZero + segment.startSeconds

        // Visibility chỉ đóng/mở cue đúng timecode. Không nội suy opacity:
        // transition và visual effect phải giữ silhouette riêng, không bị một
        // lớp fade dùng chung làm giống nhau.
        let visibilityDuration = max(segment.endSeconds + 0.01, 0.02)
        let startKey = max(0.000_001, segment.startSeconds / visibilityDuration)
        let endKey = min(0.999_999, segment.endSeconds / visibilityDuration)
        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.beginTime = AVCoreAnimationBeginTimeAtZero
        visibility.duration = visibilityDuration
        visibility.values = [0, 1, 0, 0]
        visibility.keyTimes = [0, startKey as NSNumber, endKey as NSNumber, 1]
        visibility.calculationMode = .discrete
        // Timeline opacity bắt đầu từ zero thay vì dựa vào fill của animation
        // bắt đầu muộn; nhờ vậy Core Animation export hiện đúng trong cue và
        // chắc chắn trở về 0 sau end time.
        visibility.fillMode = .both
        visibility.isRemovedOnCompletion = false
        layer.add(visibility, forKey: "cue-visibility")

        let amount = CGFloat(56 * style.effectIntensity) * renderSize.height / 1080
        if style.visualEffect == .neonAura {
            let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
            breathe.beginTime = begin
            breathe.duration = max(0.8, 1.8 / max(style.effectSpeed, 0.5))
            breathe.values = [1, 1.012, 1]
            breathe.keyTimes = [0, 0.5, 1]
            breathe.repeatCount = Float(duration / breathe.duration)
            configure(breathe)
            layer.add(breathe, forKey: "neon-breathe")
        }

        switch style.textTransition {
        case .bottomUp:
            let start = CGPoint(x: center.x, y: center.y - amount)
            let position = CAKeyframeAnimation(keyPath: "position")
            position.beginTime = begin
            position.duration = duration
            position.values = [start, center, center]
            position.keyTimes = [0, enterKey, 1]
            configure(position)
            layer.add(position, forKey: "cue-slide")
        case .softPop:
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.beginTime = begin
            scale.duration = duration
            scale.values = [0.56, 1.14, 0.96, 1.025, 1, 1]
            let settle1 = min(0.34, max(0.08, enterKey.doubleValue))
            scale.keyTimes = [0, settle1 as NSNumber, min(0.48, settle1 + 0.07) as NSNumber, min(0.58, settle1 + 0.13) as NSNumber, min(0.68, settle1 + 0.2) as NSNumber, 1]
            configure(scale)
            layer.add(scale, forKey: "cue-pop")
        case .none, .leftToRight, .rightToLeft, .wordByWord:
            break
        }
    }

    private static func addTextRevealMask(
        to container: CALayer, segment: SRTSegment, style: SubtitleBurnStyle,
        textFrame: CGRect, fontSize: CGFloat
    ) {
        let layout = SubtitleTextLayout(text: segment.text, style: style, fontSize: fontSize, size: textFrame.size)
        let steps = layout.revealSteps(text: segment.text, transition: style.textTransition)
        guard !steps.isEmpty else { return }
        let mask = CAShapeLayer()
        mask.frame = container.bounds
        mask.fillColor = NSColor.white.cgColor
        let path = CGMutablePath()
        var values: [CGPath] = [path.copy()!]
        // Bound path/keyframe growth for malformed imported giant cues.
        let stride = max(1, Int(ceil(Double(steps.count) / 256)))
        for (index, rects) in steps.enumerated() {
            for rect in rects {
                path.addRect(rect.offsetBy(dx: textFrame.minX, dy: textFrame.minY))
            }
            if (index + 1).isMultiple(of: stride) || index == steps.count - 1 {
                values.append(path.copy()!)
            }
        }
        mask.path = path
        container.mask = mask
        // Discrete Core Animation intervals end at the next key; a lone terminal
        // value at 1 is never displayed during the animation. Hold the fully
        // revealed path over the final interval as well as the forward fill.
        values.append(path.copy()!)
        let reveal = CAKeyframeAnimation(keyPath: "path")
        reveal.values = values
        reveal.keyTimes = values.indices.map { NSNumber(value: Double($0) / Double(values.count - 1)) }
        reveal.calculationMode = .discrete
        reveal.beginTime = AVCoreAnimationBeginTimeAtZero + segment.startSeconds
        reveal.duration = style.transitionEntranceDuration(forCueDuration: segment.durationSeconds)
        reveal.fillMode = .both
        reveal.isRemovedOnCompletion = false
        mask.add(reveal, forKey: "shaped-type-on")
    }

    private static func addNeonAura(
        to container: CALayer,
        textLayer: CALayer,
        segment: SRTSegment,
        style: SubtitleBurnStyle,
        scale: CGFloat
    ) {
        let tint = SubtitleBurnStyle.nsColor(fromHex: style.effectColorHex)
        for (index, radius) in [16.0, 7.0].enumerated() {
            let glow = CALayer()
            glow.frame = textLayer.frame
            glow.contents = textLayer.contents
            glow.contentsGravity = textLayer.contentsGravity
            glow.contentsScale = textLayer.contentsScale
            glow.opacity = index == 0 ? 0.34 : 0.52
            glow.shadowColor = tint.withAlphaComponent(style.effectIntensity).cgColor
            glow.shadowOpacity = 1
            glow.shadowRadius = CGFloat(radius) * scale
            glow.shadowOffset = .zero
            glow.compositingFilter = "screenBlendMode"
            container.addSublayer(glow)

            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.beginTime = AVCoreAnimationBeginTimeAtZero + segment.startSeconds
            pulse.duration = max(0.72, 1.6 / max(style.effectSpeed, 0.5))
            let low = index == 0 ? 0.2 : 0.36
            let high = min(0.9, low + 0.34 * style.effectIntensity)
            pulse.values = [low, high, low]
            pulse.keyTimes = [0, 0.5, 1]
            pulse.repeatCount = Float(max(1, segment.durationSeconds / pulse.duration))
            pulse.fillMode = .both
            pulse.isRemovedOnCompletion = false
            glow.add(pulse, forKey: "neon-pulse-\(index)")
        }
    }

    private static func addLightSweep(
        to container: CALayer,
        text: String,
        textFrame: CGRect,
        fontSize: CGFloat,
        segment: SRTSegment,
        style: SubtitleBurnStyle
    ) {
        // Core Animation video export không rasterize ổn định khi bitmap chữ
        // được dùng làm `CALayer.mask`. Dựng một bitmap glyph vàng thật rồi
        // chạy band-mask trên chính layer đó: Preview/export vẫn cùng hình học,
        // còn AVVideoComposition không thể nuốt mất sweep.
        var goldStyle = style
        goldStyle.textColorHex = style.effectColorHex
        goldStyle.outlineEnabled = false
        goldStyle.shadowEnabled = false
        let goldTextLayer = makeTextBitmapLayer(
            text: text,
            style: goldStyle,
            fontSize: fontSize,
            frame: textFrame
        )
        let gold = SubtitleBurnStyle.nsColor(fromHex: style.effectColorHex)
        goldTextLayer.opacity = Float(0.74 + 0.26 * style.effectIntensity)
        goldTextLayer.shadowColor = gold.withAlphaComponent(0.84).cgColor
        goldTextLayer.shadowOpacity = Float(0.48 + 0.36 * style.effectIntensity)
        goldTextLayer.shadowRadius = 6
        goldTextLayer.shadowOffset = .zero

        let bandMask = CAGradientLayer()
        let bandWidth = max(34, min(goldTextLayer.bounds.width * 0.16, 128))
        bandMask.bounds = CGRect(
            x: 0,
            y: 0,
            width: bandWidth,
            height: goldTextLayer.bounds.height
        )
        bandMask.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.34).cgColor,
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.34).cgColor,
            NSColor.clear.cgColor,
        ]
        bandMask.locations = [0, 0.24, 0.5, 0.76, 1]
        bandMask.startPoint = CGPoint(x: 0, y: 0.5)
        bandMask.endPoint = CGPoint(x: 1, y: 0.5)
        goldTextLayer.mask = bandMask
        container.addSublayer(goldTextLayer)

        // Position animation là primitive đã được đường native dùng ổn định;
        // dải mask hẹp quét qua bitmap glyph vàng và rời hẳn khỏi khung sau đó.
        let startX = -bandWidth / 2
        let endX = goldTextLayer.bounds.width + bandWidth / 2
        bandMask.position = CGPoint(x: endX, y: goldTextLayer.bounds.midY)
        let timing = style.goldenSweepTiming(forCueDuration: segment.durationSeconds)
        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = startX
        travel.toValue = endX
        travel.beginTime = AVCoreAnimationBeginTimeAtZero + segment.startSeconds + timing.delay
        travel.duration = timing.duration
        travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        travel.fillMode = .both
        travel.isRemovedOnCompletion = false
        bandMask.add(travel, forKey: "light-sweep")
    }

    private static func addStarlight(
        to container: CALayer,
        segment: SRTSegment,
        style: SubtitleBurnStyle,
        density: Int,
        scale: CGFloat
    ) {
        let color = SubtitleBurnStyle.nsColor(fromHex: style.effectColorHex)
        let anchors = [
            CGPoint(x: 0.08, y: 0.25), CGPoint(x: 0.27, y: 0.86),
            CGPoint(x: 0.50, y: 0.78), CGPoint(x: 0.74, y: 0.88),
            CGPoint(x: 0.92, y: 0.28), CGPoint(x: 0.82, y: 0.12),
            CGPoint(x: 0.16, y: 0.10),
        ]
        let count = min(7, max(3, density / 2 + 1))
        for index in 0..<count {
            let phase = unit(seed: segment.id &* 7_001 &+ index &* 71 &+ 47)
            let size = (10 + phase * 9) * scale
            let shape = CAShapeLayer()
            shape.path = sparklePath(size: size)
            shape.fillColor = NSColor.white.cgColor
            shape.shadowColor = color.withAlphaComponent(0.95).cgColor
            shape.shadowOpacity = Float(style.effectIntensity)
            shape.shadowRadius = 7 * scale
            shape.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let anchor = anchors[index % anchors.count]
            shape.position = CGPoint(x: container.bounds.width * anchor.x, y: container.bounds.height * anchor.y)
            shape.opacity = 0
            container.addSublayer(shape)

            let delay = min(segment.durationSeconds * 0.48, phase * segment.durationSeconds * 0.42)
            let particleDuration = max(0.34, min(segment.durationSeconds - delay, 0.8 / max(style.effectSpeed, 0.5)))
            let begin = AVCoreAnimationBeginTimeAtZero + segment.startSeconds + delay

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.beginTime = begin
            opacity.duration = particleDuration
            opacity.values = [0, style.effectIntensity, 0.28 * style.effectIntensity, style.effectIntensity, 0]
            opacity.keyTimes = [0, 0.2, 0.48, 0.72, 1]
            configure(opacity)
            shape.add(opacity, forKey: "starlight-opacity")

            let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnimation.beginTime = begin
            scaleAnimation.duration = particleDuration
            scaleAnimation.values = [0.35, 1.25, 0.72, 1, 0.25]
            scaleAnimation.keyTimes = [0, 0.2, 0.48, 0.72, 1]
            configure(scaleAnimation)
            shape.add(scaleAnimation, forKey: "starlight-scale")
        }
    }

    private static func addButterflyTrail(
        to container: CALayer,
        segment: SRTSegment,
        style: SubtitleBurnStyle,
        density: Int,
        scale: CGFloat
    ) {
        let tint = SubtitleBurnStyle.nsColor(fromHex: style.effectColorHex)
        let count = min(4, max(2, density / 5 + 1))
        for index in 0..<count {
            let size = (34 + unit(seed: segment.id &* 997 &+ index * 43) * 14) * scale
            let butterfly = makeButterflyLayer(size: size, tint: tint, scale: scale)
            butterfly.shadowColor = tint.cgColor
            butterfly.shadowOpacity = 0.92
            butterfly.shadowRadius = 7 * scale
            butterfly.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            butterfly.opacity = 0
            container.addSublayer(butterfly)

            let leftToRight = index.isMultiple(of: 2)
            let start = CGPoint(
                x: leftToRight ? -size : container.bounds.width + size,
                y: container.bounds.height * (0.18 + CGFloat(index) * 0.11)
            )
            let end = CGPoint(
                x: leftToRight ? container.bounds.width + size : -size,
                y: container.bounds.height * (0.62 - CGFloat(index) * 0.07)
            )
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: container.bounds.width * 0.28, y: container.bounds.height * 1.12),
                control2: CGPoint(x: container.bounds.width * 0.72, y: -container.bounds.height * 0.08)
            )

            let delay = min(segment.durationSeconds * 0.28, Double(index) * 0.11)
            let flightDuration = max(0.55, segment.durationSeconds - delay)
            let begin = AVCoreAnimationBeginTimeAtZero + segment.startSeconds + delay
            butterfly.zPosition = 2

            for trailIndex in 0..<2 {
                let dotSize = (5 - CGFloat(trailIndex)) * scale
                let trail = CAShapeLayer()
                trail.path = sparklePath(size: dotSize)
                trail.fillColor = tint.withAlphaComponent(0.72 - CGFloat(trailIndex) * 0.2).cgColor
                trail.shadowColor = tint.cgColor
                trail.shadowOpacity = 0.8
                trail.shadowRadius = 5 * scale
                trail.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
                trail.opacity = 0
                trail.zPosition = 1
                container.addSublayer(trail)

                let lag = Double(trailIndex + 1) * 0.08
                let trailFlight = CAKeyframeAnimation(keyPath: "position")
                trailFlight.path = path
                trailFlight.calculationMode = .paced
                trailFlight.beginTime = begin + lag
                trailFlight.duration = max(0.35, flightDuration - lag)
                configure(trailFlight)
                trail.add(trailFlight, forKey: "butterfly-trail-flight")

                let trailOpacity = CAKeyframeAnimation(keyPath: "opacity")
                trailOpacity.beginTime = begin + lag
                trailOpacity.duration = max(0.35, flightDuration - lag)
                trailOpacity.values = [0, 0.7 * style.effectIntensity, 0.34 * style.effectIntensity, 0]
                trailOpacity.keyTimes = [0, 0.12, 0.82, 1]
                configure(trailOpacity)
                trail.add(trailOpacity, forKey: "butterfly-trail-opacity")
            }

            let flight = CAKeyframeAnimation(keyPath: "position")
            flight.path = path
            flight.rotationMode = .rotateAuto
            flight.calculationMode = .paced
            flight.beginTime = begin
            flight.duration = flightDuration
            configure(flight)
            butterfly.add(flight, forKey: "butterfly-flight")

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.beginTime = begin
            opacity.duration = flightDuration
            opacity.values = [0, style.effectIntensity, style.effectIntensity, 0]
            opacity.keyTimes = [0, 0.08, 0.86, 1]
            configure(opacity)
            butterfly.add(opacity, forKey: "butterfly-opacity")

            let flap = CAKeyframeAnimation(keyPath: "transform.scale.x")
            flap.beginTime = begin
            flap.duration = 0.16 / max(style.effectSpeed, 0.5)
            flap.values = [0.42, 1, 0.56, 1]
            flap.repeatCount = Float(max(1, flightDuration / flap.duration))
            flap.fillMode = .both
            flap.isRemovedOnCompletion = false
            butterfly.add(flap, forKey: "butterfly-flap")
        }
    }

    private static func makeButterflyLayer(size: CGFloat, tint: NSColor, scale: CGFloat) -> CALayer {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: size, height: size)

        let wings = CAShapeLayer()
        wings.frame = root.bounds
        wings.path = butterflyPath(size: size)
        wings.fillColor = tint.withAlphaComponent(0.88).cgColor
        wings.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
        wings.lineWidth = max(0.8, 1.15 * scale)
        root.addSublayer(wings)

        let body = CAShapeLayer()
        let bodyPath = CGMutablePath()
        bodyPath.addRoundedRect(
            in: CGRect(x: size * 0.455, y: size * 0.2, width: size * 0.09, height: size * 0.62),
            cornerWidth: size * 0.045,
            cornerHeight: size * 0.045
        )
        body.path = bodyPath
        body.fillColor = NSColor.white.withAlphaComponent(0.94).cgColor
        root.addSublayer(body)

        let antenna = CAShapeLayer()
        let antennaPath = CGMutablePath()
        antennaPath.move(to: CGPoint(x: size * 0.48, y: size * 0.77))
        antennaPath.addCurve(
            to: CGPoint(x: size * 0.34, y: size * 0.96),
            control1: CGPoint(x: size * 0.44, y: size * 0.86),
            control2: CGPoint(x: size * 0.38, y: size * 0.92)
        )
        antennaPath.move(to: CGPoint(x: size * 0.52, y: size * 0.77))
        antennaPath.addCurve(
            to: CGPoint(x: size * 0.66, y: size * 0.96),
            control1: CGPoint(x: size * 0.56, y: size * 0.86),
            control2: CGPoint(x: size * 0.62, y: size * 0.92)
        )
        antenna.path = antennaPath
        antenna.fillColor = nil
        antenna.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        antenna.lineWidth = max(0.8, 1.1 * scale)
        antenna.lineCap = .round
        root.addSublayer(antenna)
        return root
    }

    private static func configure(_ animation: CAAnimation) {
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
    }

    private static func unit(seed: Int) -> CGFloat {
        var value = UInt64(bitPattern: Int64(seed))
        value ^= value >> 12
        value ^= value << 25
        value ^= value >> 27
        return CGFloat(value &* 2_685_821_657_736_338_717 % 10_000) / 9_999
    }

    private static func sparklePath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let center = size / 2
        path.move(to: CGPoint(x: center, y: 0))
        path.addLine(to: CGPoint(x: center * 1.18, y: center * 0.82))
        path.addLine(to: CGPoint(x: size, y: center))
        path.addLine(to: CGPoint(x: center * 1.18, y: center * 1.18))
        path.addLine(to: CGPoint(x: center, y: size))
        path.addLine(to: CGPoint(x: center * 0.82, y: center * 1.18))
        path.addLine(to: CGPoint(x: 0, y: center))
        path.addLine(to: CGPoint(x: center * 0.82, y: center * 0.82))
        path.closeSubpath()
        return path
    }

    private static func butterflyPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: size * 0.5, y: size * 0.48)
        path.move(to: center)
        path.addCurve(
            to: CGPoint(x: size * 0.08, y: size * 0.12),
            control1: CGPoint(x: size * 0.34, y: size * 0.16),
            control2: CGPoint(x: size * 0.13, y: size * 0.02)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: -size * 0.02, y: size * 0.44),
            control2: CGPoint(x: size * 0.24, y: size * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: size * 0.16, y: size * 0.88),
            control1: CGPoint(x: size * 0.28, y: size * 0.55),
            control2: CGPoint(x: size * 0.04, y: size * 0.72)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: size * 0.28, y: size * 1.02),
            control2: CGPoint(x: size * 0.42, y: size * 0.72)
        )
        path.move(to: center)
        path.addCurve(
            to: CGPoint(x: size * 0.92, y: size * 0.12),
            control1: CGPoint(x: size * 0.66, y: size * 0.16),
            control2: CGPoint(x: size * 0.87, y: size * 0.02)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: size * 1.02, y: size * 0.44),
            control2: CGPoint(x: size * 0.76, y: size * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: size * 0.84, y: size * 0.88),
            control1: CGPoint(x: size * 0.72, y: size * 0.55),
            control2: CGPoint(x: size * 0.96, y: size * 0.72)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: size * 0.72, y: size * 1.02),
            control2: CGPoint(x: size * 0.58, y: size * 0.72)
        )
        return path
    }
}
