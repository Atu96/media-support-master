import SwiftUI

enum SubtitleWorkspaceStorage {
    static let chessboardKey = "msm.subtitle.workspaceLayout"
    /// Preview (trên) và sub (dưới) chia đều chiều cao cột phải.
    static let defaultTopRowRatio: CGFloat = 0.5
    /// Cột trái (media, tóm tắt) tối thiểu — nhường chỗ cho preview + sub.
    static let defaultLeftColumnWidth: CGFloat = 240
    static let burnSlideStorageKey = "msm.subtitle.burnSlide"
    /// Panel «Kiểu sub» mở ở bề rộng tối thiểu; nhóm chỉnh xếp một cột dọc.
    static let defaultBurnSlideWidth: CGFloat = 300

    private static let legacyMigratedKey = "\(chessboardKey).legacyMigrated"

    /// Mỗi lần mở app: preview + sub chiếm tối đa; panel Kiểu sub mở nhỏ mặc định.
    static func applyLaunchLayoutDefaults() {
        let defaults = UserDefaults.standard
        let prefix = "\(chessboardKey)."

        defaults.set(Double(defaultLeftColumnWidth), forKey: "\(prefix)leftWidth")
        defaults.removeObject(forKey: "\(prefix)leftRatio")
        defaults.set(Double(defaultTopRowRatio), forKey: "\(prefix)topRatio")

        for legacy in ["msm.create.workspaceLayout", "msm.script.workspaceLayout"] {
            defaults.removeObject(forKey: "\(legacy).leftRatio")
            defaults.removeObject(forKey: "\(legacy).topRatio")
            defaults.removeObject(forKey: "\(legacy).leftWidth")
        }

        defaults.set(true, forKey: "msm.subtitle.editSlideOpen")
        defaults.set(true, forKey: "\(burnSlideStorageKey).open")
        defaults.set(Double(defaultBurnSlideWidth), forKey: "\(burnSlideStorageKey).width")

        defaults.set(false, forKey: "msm.logConsoleExpanded.create")
        defaults.set(false, forKey: "msm.logConsoleExpanded.script")
    }

    /// Gộp layout cũ (một lần) — không chạy lại sau launch defaults.
    static func migrateLegacyChessboardLayoutIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyMigratedKey) else { return }

        let prefix = "\(chessboardKey)."
        guard defaults.object(forKey: "\(prefix)leftWidth") == nil,
              defaults.object(forKey: "\(prefix)leftRatio") == nil else {
            defaults.set(true, forKey: legacyMigratedKey)
            return
        }

        for legacy in ["msm.create.workspaceLayout", "msm.script.workspaceLayout"] {
            guard defaults.object(forKey: "\(legacy).leftRatio") != nil
                || defaults.object(forKey: "\(legacy).leftWidth") != nil else { continue }
            if defaults.object(forKey: "\(legacy).leftWidth") != nil {
                defaults.set(defaults.double(forKey: "\(legacy).leftWidth"), forKey: "\(prefix)leftWidth")
            } else {
                defaults.set(defaults.double(forKey: "\(legacy).leftRatio"), forKey: "\(prefix)leftRatio")
            }
            if defaults.object(forKey: "\(legacy).topRatio") != nil {
                defaults.set(defaults.double(forKey: "\(legacy).topRatio"), forKey: "\(prefix)topRatio")
            }
            break
        }
        defaults.set(true, forKey: legacyMigratedKey)
    }
}

enum SubtitleModuleTab: String, CaseIterable, Identifiable {
    case create
    case script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Tạo sub tự động"
        case .script: "Khớp văn bản gốc"
        }
    }

    var icon: String {
        switch self {
        case .create: "waveform"
        case .script: "doc.text"
        }
    }

    var appSection: AppSection {
        switch self {
        case .create: .subtitleCreate
        case .script: .subtitleScript
        }
    }
}
