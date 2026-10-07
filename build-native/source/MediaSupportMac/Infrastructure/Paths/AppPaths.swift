import Foundation

/// Đường dẫn runtime — đọc một lần, không hardcode rải rác.
enum AppPaths {
    static let appRoot: URL = {
        if let configured = ProcessInfo.processInfo.environment["APP_ROOT"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        }
        let candidate = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("scripts/common.sh").path) {
            return candidate
        }
        return URL(fileURLWithPath: "\(NSHomeDirectory())/Documents/Media Support App")
    }()
    static let toolsRoot = URL(fileURLWithPath: "\(NSHomeDirectory())/Documents/Tools")
    static let resourcesRoot = URL(fileURLWithPath: "\(NSHomeDirectory())/Documents/Resources")
    static let whisperHome = toolsRoot.appendingPathComponent("Whisper_Native", isDirectory: true)
    static let videoScripts = toolsRoot.appendingPathComponent("VideoSegmentCutter/scripts", isDirectory: true)
    static let scriptsDir = appRoot.appendingPathComponent("scripts", isDirectory: true)

    static var runtimeRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Media Support Master", isDirectory: true)
    }

    static var logsDir: URL {
        runtimeRoot.appendingPathComponent("logs", isDirectory: true)
    }

    static func ensureRuntimeDirs() {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        ProjectBackupStore.ensureLayout()
    }

    static var backupRoot: URL {
        BackupPreferences.shared.backupRootURL
    }

    static func resolveFFmpeg() -> String? {
        // Homebrew trước — codec đầy đủ; bundled playwright chỉ fallback
        let candidates: [String] = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "ffmpeg")?.path,
            Bundle.main.url(forResource: "ffmpeg-mac", withExtension: nil, subdirectory: "ffmpeg")?.path,
            resourcesRoot
                .appendingPathComponent("Contents/Resources/PlaywrightBrowsers/ffmpeg-1011/ffmpeg-mac")
                .path
        ].compactMap { $0 }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static func engineStatus() -> EngineStatus {
        var issues: [String] = []
        if !FileManager.default.fileExists(atPath: toolsRoot.path) {
            issues.append("Thiếu ~/Documents/Tools")
        }
        if !FileManager.default.fileExists(atPath: whisperHome.path) {
            issues.append("Thiếu Whisper_Native")
        }
        let model = whisperHome.appendingPathComponent("ggml-large-v3-turbo.bin")
        if !FileManager.default.fileExists(atPath: model.path) {
            issues.append("Thiếu Whisper model")
        }
        let venv = whisperHome.appendingPathComponent("venv/bin/python")
        if !FileManager.default.isExecutableFile(atPath: venv.path) {
            issues.append("Thiếu venv Python")
        }
        if resolveFFmpeg() == nil {
            issues.append("Thiếu ffmpeg")
        }
        let cutEngine = videoScripts.appendingPathComponent("cut_batch_interleave.sh")
        if !FileManager.default.isExecutableFile(atPath: cutEngine.path) {
            issues.append("Thiếu cut_batch_interleave.sh")
        }
        return EngineStatus(isReady: issues.isEmpty, issues: issues)
    }
}
