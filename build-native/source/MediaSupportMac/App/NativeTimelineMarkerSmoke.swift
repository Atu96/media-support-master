import Foundation

/// TEST-only pure manifest contract; no preferences, project store, media or API.
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
        print("TIMELINE_MARKER_SMOKE_OK oldManifest=compatible note=Unicode preservedProjectFields=true delete=retained noKey=true noAPI=true")
    }
}
