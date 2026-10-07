import Foundation

enum AppRuntimeRootResolver {
    static func resolve(configured: String?, bundleURL: URL, resourceURL: URL?, home: URL) -> URL {
        if let configured, !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        }
        let bundled = resourceURL?.appendingPathComponent("Runtime", isDirectory: true)
        let checkout = bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for candidate in [bundled, checkout].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("scripts/common.sh").path) {
                return candidate
            }
        }
        return home.appendingPathComponent("Documents/Media Support App", isDirectory: true)
    }
}
