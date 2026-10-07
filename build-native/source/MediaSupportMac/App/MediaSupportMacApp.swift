import AppKit

@main
@MainActor
enum MediaSupportMacLauncher {
    static func main() {
        if Bundle.main.object(forInfoDictionaryKey:"MediaSupportBuildChannel") as? String == "test",
           let path=ProcessInfo.processInfo.environment["MSM_INTEGRATED_TOOLS_SMOKE_DIR"] {
            Task {
                do { try await NativeIntegratedToolsSmoke.run(directory:URL(fileURLWithPath:path));exit(0) }
                catch { print("NATIVE_SMOKE_FAILED: \(error.localizedDescription)");exit(1) }
            }
            RunLoop.main.run()
            return
        }
        AppLanguagePreference.prepareForLaunch()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
