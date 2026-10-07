import AppKit

/// Dọn tài nguyên trước khi thoát — gọi một lần.
@MainActor
enum AppShutdown {
    private static var didRun = false

    static func perform() {
        guard !didRun else { return }
        didRun = true
        AppCoordinator.shared.shutdownForQuit()
    }
}