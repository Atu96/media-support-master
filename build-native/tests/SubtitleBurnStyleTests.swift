import Foundation

@main
enum SubtitleBurnStyleTests {
    static func main() throws {
        var style = SubtitleBurnStyle()
        precondition(!style.fadeInEnabled)
        precondition(!style.fadeOutEnabled)
        style.fadeInEnabled = false
        style.fadeOutEnabled = true
        style.fadeInMs = 350
        style.fadeOutMs = 600
        style.outlineEnabled = true
        style.outlineColorHex = "#112233"
        style.outlineOpacity = 0.8
        style.outlineWidth = 5
        style.shadowEnabled = true
        style.shadowColorHex = "#445566"
        style.shadowOpacity = 0.75
        style.shadowBlur = 4
        style.shadowDistance = 7
        style.shadowAngle = 315
        style.textTransition = .rightToLeft
        style.visualEffect = .butterflyTrail
        style.effectIntensity = 0.8
        style.effectSpeed = 1.25
        style.effectDensity = 12
        style.effectColorHex = "#88CCFF"

        let xmlArgs = argumentMap(style.fcpxmlCLIArgs)
        precondition(xmlArgs["--fade-in-ms"] == "0")
        precondition(xmlArgs["--fade-out-ms"] == "0")
        precondition(xmlArgs["--outline-color"] == "0.067 0.133 0.200 0.800")
        precondition(xmlArgs["--outline-width"] == "5")
        precondition(xmlArgs["--shadow-color"] == "0.267 0.333 0.400 0.750")
        precondition(xmlArgs["--shadow-distance"] == "7")
        precondition(xmlArgs["--shadow-angle"] == "315")

        let burnArgs = argumentMap(style.burnCLIArgs)
        precondition(burnArgs["--fade-in"] == "0")
        precondition(burnArgs["--fade-out"] == "0")
        precondition(burnArgs["--outline-color"] == "#112233")
        precondition(burnArgs["--outline-opacity"] == "0.80")
        precondition(burnArgs["--outline-width"] == "5")
        precondition(burnArgs["--shadow-color"] == "#445566")
        precondition(burnArgs["--shadow-opacity"] == "0.75")
        precondition(burnArgs["--shadow-blur"] == "4")
        precondition(burnArgs["--shadow-distance"] == "7")
        precondition(burnArgs["--shadow-angle"] == "315")
        precondition(burnArgs["--effect-preset"] == "butterfly")
        precondition(burnArgs["--text-transition"] == "rightToLeft")
        precondition(burnArgs["--visual-effect"] == "butterflyTrail")
        precondition(burnArgs["--effect-intensity"] == "0.80")
        precondition(burnArgs["--effect-speed"] == "1.25")
        precondition(burnArgs["--effect-density"] == "12")
        precondition(burnArgs["--effect-color"] == "#88CCFF")

        let revealDuration = style.transitionEntranceDuration(forCueDuration: 3.4)
        precondition(abs(revealDuration - 0.448) < 0.001)
        let goldenTiming = style.goldenSweepTiming(forCueDuration: 3.4)
        precondition(abs(goldenTiming.delay - 0.516) < 0.001)
        precondition(abs(goldenTiming.duration - 0.736) < 0.001)
        precondition(goldenTiming.delay > revealDuration)
        precondition(goldenTiming.delay + goldenTiming.duration < 3.4)

        let encoded = try JSONEncoder().encode(style)
        let restored = try JSONDecoder().decode(SubtitleBurnStyle.self, from: encoded)
        precondition(!restored.fadeInEnabled)
        precondition(restored.fadeOutEnabled)
        precondition(restored.outlineEnabled && restored.outlineWidth == 5)
        precondition(restored.shadowEnabled && restored.shadowDistance == 7)
        precondition(restored.textTransition == .rightToLeft)
        precondition(restored.visualEffect == .butterflyTrail)
        precondition(restored.effectDensity == 12)

        let legacyOff = Data(#"{"fadeEnabled":false,"fadeInMs":200,"fadeOutMs":200}"#.utf8)
        let migrated = try JSONDecoder().decode(SubtitleBurnStyle.self, from: legacyOff)
        precondition(!migrated.fadeInEnabled)
        precondition(!migrated.fadeOutEnabled)
        precondition(migrated.effectPreset == .none)

        let legacySlide = Data(#"{"effectPreset":"softSlide"}"#.utf8)
        let migratedSlide = try JSONDecoder().decode(SubtitleBurnStyle.self, from: legacySlide)
        precondition(migratedSlide.textTransition == .leftToRight)
        precondition(migratedSlide.visualEffect == .none)
        let legacyGlow = Data(#"{"effectPreset":"gentleFloat"}"#.utf8)
        let migratedGlow = try JSONDecoder().decode(SubtitleBurnStyle.self, from: legacyGlow)
        precondition(migratedGlow.textTransition == .none)
        precondition(migratedGlow.visualEffect == .neonAura)
        precondition(SubtitleTextTransition.allCases.count == 6)
        precondition(SubtitleVisualEffect.allCases.count == 5)
        precondition(SubtitleEffectPreset.allCases.count == 7)
        precondition(!SubtitleEffectPreset.allCases.contains(.softSlide))

        print("✓ Subtitle style regression OK — transition/effect độc lập, app-only không fade, FCPXML sạch")
    }

    private static func argumentMap(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < args.count {
            let key = args[index]
            if key.hasPrefix("--"), args[index + 1].hasPrefix("--") == false {
                result[key] = args[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }
}
