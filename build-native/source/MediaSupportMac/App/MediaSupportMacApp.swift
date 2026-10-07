import AppKit

@main
@MainActor
enum MediaSupportMacLauncher {
    static func main() {
        AppLanguagePreference.prepareForLaunch()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
