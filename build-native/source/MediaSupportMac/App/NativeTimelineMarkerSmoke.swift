import Foundation
import SwiftUI
import AppKit

/// TEST-only manifest contract and optional flag previews; no project store, media or API.
@MainActor
enum NativeTimelineMarkerSmoke {
    static func run() throws {
        func check(_ value: Bool) throws { if !value { throw DubbingError.invalidAudioBuffer } }
        let date = Date(timeIntervalSince1970: 0)
        let original = ProjectBackupManifest(id: "fixture", mediaPath: "/invalid/fixture.mov",
            mediaDisplayName: "fixture.mov", artifacts: ProjectBackupArtifacts(), lang: nil,
            progress: .init(), prefs: .init(), completionSummary: "fixture", burnStyle: .init(),
            createdAt: date, updatedAt: date)
        let encoded = try JSONEncoder().encode(original)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "markers")
        let old = try JSONDecoder().decode(ProjectBackupManifest.self,
            from: JSONSerialization.data(withJSONObject: json))
        try check(old.markers == nil && old.id == original.id && old.version == original.version)
        var saved = old
        saved.markers = [.init(seconds: 4.25, note: "Dịch lại\n日本語 한국어 中文 🎙️")]
        let restored = try JSONDecoder().decode(ProjectBackupManifest.self, from: JSONEncoder().encode(saved))
        try check(restored.markers == saved.markers && restored.artifacts == old.artifacts
                  && restored.progress == old.progress && restored.prefs == old.prefs
                  && restored.burnStyle == old.burnStyle && restored.mediaPath == old.mediaPath)
        var removed = restored
        removed.markers = []
        let cleared = try JSONDecoder().decode(ProjectBackupManifest.self, from: JSONEncoder().encode(removed))
        try check(cleared.markers?.isEmpty == true && cleared.completionSummary == old.completionSummary)
        if let directory = ProcessInfo.processInfo.environment["MSM_TIMELINE_MARKER_PREVIEW_DIR"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for dark in [true, false] {
                let content = ZStack(alignment: .topLeading) {
                    (dark ? Color(white: 0.14) : Color(white: 0.94))
                    Rectangle().fill(Color.red).frame(width: 1.5, height: 48).offset(x: 96)
                    TimelineMarkerFlag(poleX: 0.75)
                    TimelineMarkerFlag().offset(x: 84)
                    TimelineMarkerFlag(poleX: 23.25).offset(x: 168)
                }
                .frame(width: 192, height: 48)
                .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 3
                guard let data = renderer.nsImage?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw DubbingError.invalidAudioBuffer
                }
                try png.write(to: root.appendingPathComponent(dark ? "marker-flag-dark.png" : "marker-flag-light.png"))
            }
        }
        print("TIMELINE_MARKER_SMOKE_OK oldManifest=compatible note=Unicode preservedProjectFields=true delete=retained noKey=true noAPI=true")
    }
}
