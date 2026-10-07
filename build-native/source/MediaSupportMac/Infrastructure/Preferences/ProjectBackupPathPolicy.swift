import CryptoKit
import Foundation

/// Quy tắc tên và đường dẫn dự án. Tất cả hàm ở đây là pure:
/// không tạo/xóa/di chuyển file và không đọc preferences.
enum ProjectBackupPathPolicy {
    static func projectID(for media: URL) -> String {
        let path = media.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func projectFolderSlug(for media: URL) -> String {
        let raw = projectBundleName(for: media)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        var built = String(raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
        built = built.replacingOccurrences(of: " ", with: "_")
        while built.contains("--") {
            built = built.replacingOccurrences(of: "--", with: "-")
        }
        built = built.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if built.count > 40 {
            built = String(built.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        }
        return built.isEmpty ? "project" : built
    }

    static func projectBundleName(for media: URL) -> String {
        let raw = media.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Untitled" : raw
    }

    static func translatedFilenameSuffix(targetLang: String?) -> String {
        guard let raw = targetLang?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else { return "" }
        return "_\(raw)"
    }

    static func coLocatedDeliverableURL(
        for media: URL,
        targetLang: String?,
        extension ext: String
    ) -> URL {
        let base = projectBundleName(for: media)
        let suffix = translatedFilenameSuffix(targetLang: targetLang)
        return media.deletingLastPathComponent()
            .appendingPathComponent("\(base)\(suffix)")
            .appendingPathExtension(ext)
    }

    static func exportBundleDir(for media: URL) -> URL {
        let name = projectBundleName(for: media)
        let parent = media.deletingLastPathComponent().standardizedFileURL
        if parent.lastPathComponent == name {
            return parent
        }
        return parent.appendingPathComponent(name, isDirectory: true)
    }

    static func bundleMediaURL(for media: URL) -> URL {
        exportBundleDir(for: media).appendingPathComponent(media.lastPathComponent)
    }
}
