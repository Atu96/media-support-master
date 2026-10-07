import Foundation

/// Đường dẫn runtime — đọc một lần, không hardcode rải rác.
enum AppPaths {
    static let appRoot = AppRuntimeRootResolver.resolve(
        configured: ProcessInfo.processInfo.environment["APP_ROOT"],
        bundleURL: Bundle.main.bundleURL,
        resourceURL: Bundle.main.resourceURL,
        home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    )
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
        if (try? NativeWhisperRuntime.engineURL()) == nil { issues.append("Thiếu engine Whisper trong ứng dụng") }
        if !OfflineWhisperModelManager.isModelReady,
           !FileManager.default.fileExists(atPath:whisperHome.appendingPathComponent(OfflineWhisperModelManager.modelFileName).path) {
            issues.append("Chưa tải model Whisper Offline")
        }
        return EngineStatus(isReady: issues.isEmpty, issues: issues)
    }
}
