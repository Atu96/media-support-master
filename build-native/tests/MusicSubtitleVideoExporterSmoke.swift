import Foundation

@main
@MainActor
enum MusicSubtitleVideoExporterSmoke {
    static func main() async throws {
        guard (3...5).contains(CommandLine.arguments.count) else {
            print("usage: MusicSubtitleVideoExporterSmoke <input-video> <output-video> [transition-raw-value] [visual-effect-raw-value]")
            return
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let segments = [
            SRTSegment(
                id: 1,
                index: 1,
                timing: "00:00:00,300 --> 00:00:03,700",
                startSeconds: 0.3,
                endSeconds: 3.7,
                text: "Lời ca bay nhẹ\ntrong ánh sáng"
            ),
            SRTSegment(
                id: 2,
                index: 2,
                timing: "00:00:04,000 --> 00:00:07,500",
                startSeconds: 4,
                endSeconds: 7.5,
                text: "Bươm bướm theo nhịp nhạc"
            ),
        ]
        var style = SubtitleBurnStyle()
        style.fontName = "AvenirNext-DemiBold"
        style.boxEnabled = false
        style.outlineEnabled = true
        style.outlineWidth = 3
        style.shadowEnabled = true
        style.shadowBlur = 3
        style.shadowDistance = 5
        style.marginBottom = 76
        style.textTransition = CommandLine.arguments.count >= 4
            ? (SubtitleTextTransition(rawValue: CommandLine.arguments[3]) ?? .leftToRight)
            : .leftToRight
        style.visualEffect = CommandLine.arguments.count == 5
            ? (SubtitleVisualEffect(rawValue: CommandLine.arguments[4]) ?? .butterflyTrail)
            : .butterflyTrail
        style.effectIntensity = 0.72
        style.effectDensity = 8
        switch style.visualEffect {
        case .none: style.effectColorHex = "#8FD3FF"
        case .goldenSweep: style.effectColorHex = "#FFD66B"
        case .neonAura: style.effectColorHex = "#37D7FF"
        case .starlight: style.effectColorHex = "#B7A8FF"
        case .butterflyTrail: style.effectColorHex = "#62E6BE"
        }
        try await SubtitleVideoExporter.export(
            videoURL: input,
            outputURL: output,
            segments: segments,
            style: style
        )
        print("✓ Native music subtitle smoke → \(output.path)")
    }
}
