import Foundation

/// Cài đặt vault backup dự án — kiểu Final Cut Pro (vị trí tùy chọn, xóa chủ động).
final class BackupPreferences: ObservableObject {
    static let shared = BackupPreferences()

    private let rootKey = "msm.backupRoot"
    private let mirrorSRTKey = "msm.mirrorSRTBesideMedia"
    private let mirrorSubbedKey = "msm.mirrorSubbedBesideMedia"
    private let autoPurgeKey = "msm.autoPurgeBackupOnBurn"
    private let retentionKey = "msm.backupRetentionDays"

    static let defaultBackupFolderName = "Media Support Backups"

    @Published var backupRootURL: URL {
        didSet {
            UserDefaults.standard.set(backupRootURL.path, forKey: rootKey)
            ProjectBackupStore.ensureLayout()
        }
    }

    @Published var mirrorSRTBesideMedia: Bool {
        didSet { UserDefaults.standard.set(mirrorSRTBesideMedia, forKey: mirrorSRTKey) }
    }

    @Published var mirrorSubbedBesideMedia: Bool {
        didSet { UserDefaults.standard.set(mirrorSubbedBesideMedia, forKey: mirrorSubbedKey) }
    }

    @Published var autoPurgeBackupOnBurn: Bool {
        didSet { UserDefaults.standard.set(autoPurgeBackupOnBurn, forKey: autoPurgeKey) }
    }

    /// 0 = giữ đến khi xóa thủ công
    @Published var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: retentionKey) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: rootKey), !saved.isEmpty {
            backupRootURL = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            backupRootURL = Self.defaultBackupRoot()
        }
        mirrorSRTBesideMedia = UserDefaults.standard.object(forKey: mirrorSRTKey) as? Bool ?? false
        mirrorSubbedBesideMedia = UserDefaults.standard.object(forKey: mirrorSubbedKey) as? Bool ?? true
        autoPurgeBackupOnBurn = UserDefaults.standard.object(forKey: autoPurgeKey) as? Bool ?? true
        retentionDays = UserDefaults.standard.object(forKey: retentionKey) as? Int ?? 30
    }

    static func defaultBackupRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/\(defaultBackupFolderName)", isDirectory: true)
    }

    var retentionLabel: String {
        retentionDays <= 0 ? "Đến khi xóa thủ công" : "\(retentionDays) ngày"
    }
}