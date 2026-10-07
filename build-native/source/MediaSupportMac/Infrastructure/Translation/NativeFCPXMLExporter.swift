import Foundation

/// Native FCPXML preserves the existing Motion parameter contract.
enum NativeFCPXMLExporter {
    static func render(segments: [SRTSegment], name: String, style: SubtitleBurnStyle,
                       templateURL: URL) throws -> String {
        let cues = segments.filter { $0.endSeconds > $0.startSeconds }
        guard !cues.isEmpty, cues.allSatisfy({ $0.startSeconds.isFinite && $0.endSeconds.isFinite && $0.startSeconds >= 0 && $0.endSeconds <= 9e12 }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let args = style.fcpxmlCLIArgs
        var a: [String:String] = [:]
        for i in stride(from: 0, to: args.count - 1, by: 2) { a[args[i]] = args[i+1] }
        let fps: (Int64,Int64)
        switch style.fps {
        case "25": fps = (1,25)
        case "30": fps = (1,30)
        case "48": fps = (1,48)
        case "60": fps = (1,60)
        case "2997": fps = (1001,30000)
        case "2398": fps = (1001,24000)
        default: fps = (1,24)
        }
        func time(_ seconds: Double) -> String {
            fraction(Int64((seconds * Double(fps.1) / Double(fps.0)).rounded(.toNearestOrEven)) * fps.0, fps.1)
        }
        let width = max(40, min(100, style.boxMaxWidthPercent))
        let scale_x = String(format: "%.4f", locale: Locale(identifier:"en_US_POSIX"), 1.0301 * Double(width) / 92)
        let scale_y = "0.9500"
        let opacity = String(format:"%.4f", locale: Locale(identifier:"en_US_POSIX"), Double(a["--bg-opacity"] ?? "0") ?? 0)
        let bg_color = a["--bg-color"] ?? "0 0 0 1"
        let corner_radius = String(max(0,min(100,style.boxCornerRadius)))
        let pos_y = String(style.resolvedFcpxmlPositionY)
        let bottom_margin = "-192.3560"
        let parts = style.fcpxmlFontParts
        let bold = ["bold","semibold","demibold","heavy","black","w6","w7","w8","w9"].contains(parts.face.lowercased().replacingOccurrences(of:" ",with:"")) ? "1" : "0"
        var titles: [String] = []
        for (index,cue) in cues.enumerated() {
            try Task.checkCancellation()
            let two = cue.text.components(separatedBy:"\n").filter { !$0.trimmingCharacters(in:.whitespaces).isEmpty }.count > 1
            let params: String
            if two {
                params = """
                <param name="Hiệu ứng vào" key="9999/10000/2/101" value="0"/>
                <param name="Hiệu ứng ra" key="9999/10000/2/102" value="0"/>
                <param name="Fade In Time" key="9999/10003/12450/200" value="0"/>
                <param name="Fade Out Time" key="9999/10003/12450/201" value="0"/>
                <param name="Rộng nền" key="9999/10003/10043/1/100/105/1" value="\(scale_x)"/>
                <param name="Cao nền" key="9999/10003/10043/1/100/105/2" value="\(scale_y)"/>
                <param name="Độ trong suốt" key="9999/10003/10043/2/353/113/141" value="\(opacity)"/>
                <param name="Màu nền" key="9999/10003/10043/2/353/113/111" value="\(bg_color)"/>
                <param name="Độ nhọn viền" key="9999/10003/10043/2/353/144" value="\(corner_radius)"/>
                <param name="Position" key="9999/10003/10065/1/100/101" value="0 \(pos_y)"/>
                <param name="Anchor Point" key="9999/10003/10065/1/100/107" value="862.491 -96.1779"/>
                <param name="Layout Method" key="9999/10003/10065/2/314" value="1 (Paragraph)"/>
                <param name="Right Margin" key="9999/10003/10065/2/324" value="1724.98"/>
                <param name="Bottom Margin" key="9999/10003/10065/2/326" value="\(bottom_margin)"/>
                <param name="Alignment" key="9999/10003/10065/2/354/10038/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/354/3001947110/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/373" value="0 (Left) 1 (Middle)"/>
"""
            } else {
                params = """
                <param name="Hiệu ứng vào" key="9999/10000/2/101" value="0"/>
                <param name="Hiệu ứng ra" key="9999/10000/2/102" value="0"/>
                <param name="Fade In Time" key="9999/10003/12450/200" value="0"/>
                <param name="Fade Out Time" key="9999/10003/12450/201" value="0"/>
                <param name="Rộng nền" key="9999/10003/10043/1/100/105/1" value="\(scale_x)"/>
                <param name="Cao nền" key="9999/10003/10043/1/100/105/2" value="\(scale_y)"/>
                <param name="Độ trong suốt" key="9999/10003/10043/2/353/113/141" value="\(opacity)"/>
                <param name="Màu nền" key="9999/10003/10043/2/353/113/111" value="\(bg_color)"/>
                <param name="Độ nhọn viền" key="9999/10003/10043/2/353/144" value="\(corner_radius)"/>
                <param name="Position" key="9999/10003/10065/1/100/101" value="0 \(pos_y)"/>
                <param name="Anchor Point" key="9999/10003/10065/1/100/107" value="862.491 -96.1779"/>
                <param name="Layout Method" key="9999/10003/10065/2/314" value="1 (Paragraph)"/>
                <param name="Right Margin" key="9999/10003/10065/2/324" value="1724.98"/>
                <param name="Bottom Margin" key="9999/10003/10065/2/326" value="\(bottom_margin)"/>
                <param name="Alignment" key="9999/10003/10065/2/354/10038/401" value="1 (Center)"/>
                <param name="Alignment" key="9999/10003/10065/2/373" value="0 (Left) 1 (Middle)"/>
"""
            }
            let ts = "ts\(index+1)"
            var fade = ""
            let half = Int((cue.endSeconds-cue.startSeconds)*500)
            let enter = min(half,Int(a["--fade-in-ms"] ?? "0") ?? 0)
            let exit = min(half,Int(a["--fade-out-ms"] ?? "0") ?? 0)
            if enter > 0 || exit > 0 {
                fade = "<param name=\"Opacity\" key=\"9999/10003/1/200/202\" value=\"1\">"
                if enter > 0 { fade += "<fadeIn type=\"easeInOut\" duration=\"\(fraction(Int64(enter),1000))\"/>" }
                if exit > 0 { fade += "<fadeOut type=\"easeInOut\" duration=\"\(fraction(Int64(exit),1000))\"/>" }
                fade += "</param>"
            }
            titles.append("""
<title ref="r2" lane="1" offset="\(time(cue.startSeconds))" name="\(escape(String((cue.text.components(separatedBy:"\n").first ?? "").prefix(40)))) - Phu de nen den" duration="\(time(cue.endSeconds-cue.startSeconds))">
\(fade)
\(params)
<text><text-style ref="\(ts)">\(escape(cue.text))</text-style></text>
<text-style-def id="\(ts)"><text-style font="\(escape(parts.family))" fontSize="\(max(18,min(200,style.fontSize)))" fontFace="\(escape(parts.face))" fontColor="\(a["--font-color"]!)" strokeColor="\(a["--outline-color"]!)" strokeWidth="\(-abs(Int(a["--outline-width"]!)!))" shadowColor="\(a["--shadow-color"]!)" shadowOffset="\(a["--shadow-distance"]!) \(a["--shadow-angle"]!)" bold="\(bold)" alignment="center"/></text-style-def>
</title>
""")
        }
        let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="1.11"><resources>
<format id="r1" name="FFVideoFormat1080p\(fps.1)" frameDuration="\(fraction(fps.0,fps.1))" width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/>
<effect id="r2" name="Phu de nen den" uid="~/Titles.localized/Phu de nen den/Phu de nen den.moti" src="\(escape(templateURL.absoluteString))"/>
</resources><library><event name="Subtitles"><project name="\(escape(name))"><sequence format="r1" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k"><spine><gap name="Gap" offset="0s" duration="\(time(cues.map(\.endSeconds).max()!))">
\(titles.joined(separator:"\n"))
</gap></spine></sequence></project></event></library></fcpxml>
"""
        _ = try XMLDocument(xmlString: xml, options: [])
        return xml
    }
    private static func fraction(_ num: Int64,_ den: Int64) -> String {
        var x=abs(num), y=den
        while y != 0 { let r=x%y; x=y; y=r }
        let n=num/max(1,x), d=den/max(1,x)
        return d == 1 ? "\(n)s" : "\(n)/\(d)s"
    }
    private static func escape(_ text:String) -> String {
        text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;")
            .replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
    }
}
