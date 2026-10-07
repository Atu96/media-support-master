@preconcurrency import Foundation
import CryptoKit

enum OfflineWhisperModelStatus: Equatable {
    case notInstalled
    case downloading
    case verifying
    case ready
    case failed(String)
}

@MainActor
final class OfflineWhisperModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = OfflineWhisperModelManager()

    nonisolated static let modelName = "Whisper Large V3 Turbo"
    nonisolated static let modelFileName = "ggml-large-v3-turbo.bin"
    nonisolated static let expectedBytes: Int64 = 1_624_555_275
    nonisolated static let expectedSHA256 = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
    nonisolated static let sourceRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    nonisolated static let sourceURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(sourceRevision)/ggml-large-v3-turbo.bin"
    )!

    @Published private(set) var status: OfflineWhisperModelStatus = .notInstalled
    @Published private(set) var progress: Double = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = expectedBytes

    private var downloadTask: URLSessionDownloadTask?
    private var importTask: Task<Void,Error>?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 8
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    nonisolated static var modelsDirectory: URL {
        AppPaths.runtimeRoot
            .appendingPathComponent("OfflineModels", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    nonisolated static var modelURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    nonisolated static var partialURL: URL {
        modelsDirectory.appendingPathComponent("\(modelFileName).download")
    }

    nonisolated static var isModelReady: Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "msm.offlineWhisper.verifiedSHA256") == expectedSHA256,
              let values = try? modelURL.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey]),
              let size=values.fileSize,let modified=values.contentModificationDate else {
            return false
        }
        return Int64(size) == expectedBytes
            && abs(modified.timeIntervalSince1970-defaults.double(forKey:"msm.offlineWhisper.verifiedModifiedTime"))<0.00001
    }

    private override init() {
        super.init()
        refreshStatus()
    }

    func refreshStatus() {
        guard downloadTask == nil,importTask == nil else { return }
        status = Self.isModelReady ? .ready : .notInstalled
        progress = Self.isModelReady ? 1 : 0
        downloadedBytes = Self.isModelReady ? Self.expectedBytes : 0
        totalBytes = Self.expectedBytes
    }

    func startDownload() {
        if case .verifying = status { return }
        guard downloadTask == nil, !Self.isModelReady else { return }
        do {
            try FileManager.default.createDirectory(
                at: Self.modelsDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: Self.partialURL)
        } catch {
            status = .failed("Không tạo được thư mục lưu model: \(error.localizedDescription)")
            return
        }
        progress = 0
        downloadedBytes = 0
        totalBytes = Self.expectedBytes
        status = .downloading
        let task = session.downloadTask(with: Self.sourceURL)
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: Self.partialURL)
        status = .notInstalled
        progress = 0
        downloadedBytes = 0
    }

    /// Reuse a verified legacy model once; hard-link avoids another 1.62 GB download/copy.
    static func ensureAvailableModel() async throws -> URL {
        if isModelReady { return modelURL }
        let manager = shared
        if let current=manager.importTask { try await current.value;return modelURL }
        guard manager.downloadTask == nil else { throw OfflineWhisperError.modelNotInstalled }
        let legacy = FileManager.default.fileExists(atPath:modelURL.path) ? modelURL : AppPaths.whisperHome.appendingPathComponent(modelFileName)
        guard FileManager.default.fileExists(atPath: legacy.path) else { throw OfflineWhisperError.modelNotInstalled }
        manager.status = .verifying
        let worker = Task.detached(priority: .utility) {
            let fm = FileManager.default
            let before = try legacy.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey])
            guard Int64(before.fileSize ?? 0) == expectedBytes, try sha256(of: legacy) == expectedSHA256,
                  try legacy.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate==before.contentModificationDate else {
                throw OfflineWhisperModelError.invalidChecksum
            }
            try Task.checkCancellation()
            if legacy==modelURL { return }
            try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            let stage = modelsDirectory.appendingPathComponent("import-\(UUID().uuidString).bin")
            defer { try? fm.removeItem(at: stage) }
            do { try fm.linkItem(at: legacy, to: stage) }
            catch { try fm.copyItem(at: legacy, to: stage) }
            try Task.checkCancellation()
            if fm.fileExists(atPath: modelURL.path) {
                _ = try fm.replaceItemAt(modelURL, withItemAt: stage)
            } else { try fm.moveItem(at: stage, to: modelURL) }
        }
        manager.importTask=worker
        do {
            try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            UserDefaults.standard.set(expectedSHA256, forKey:"msm.offlineWhisper.verifiedSHA256")
            let modified=try modelURL.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
            UserDefaults.standard.set(modified,forKey:"msm.offlineWhisper.verifiedModifiedTime")
            manager.importTask=nil
            manager.refreshStatus()
            return modelURL
        } catch {
            manager.importTask=nil
            manager.refreshStatus()
            throw error
        }
    }

    func deleteModel() throws {
        cancelDownload()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.modelURL.path) {
            try fileManager.removeItem(at: Self.modelURL)
        }
        try? fileManager.removeItem(at: Self.partialURL)
        UserDefaults.standard.removeObject(forKey: "msm.offlineWhisper.verifiedSHA256")
        refreshStatus()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.downloadTask === downloadTask else { return }
            self.downloadedBytes = totalBytesWritten
            let expected = totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite
                : Self.expectedBytes
            self.totalBytes = expected
            self.progress = min(1, max(0, Double(totalBytesWritten) / Double(expected)))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let staged = Self.partialURL
        do {
            try FileManager.default.createDirectory(
                at: Self.modelsDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            Task { @MainActor [weak self] in
                self?.finishWithFailure("Không lưu được file tải: \(error.localizedDescription)")
            }
            return
        }

        Task { @MainActor [weak self] in
            await self?.verifyAndInstall(staged)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let code = (error as? URLError)?.code
        guard code != .cancelled else { return }
        Task { @MainActor [weak self] in
            self?.finishWithFailure("Tải model thất bại: \(error.localizedDescription)")
        }
    }

    private func verifyAndInstall(_ staged: URL) async {
        status = .verifying
        progress = 1
        do {
            let result = try await Task.detached(priority: .utility) {
                let values = try staged.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(values.fileSize ?? 0)
                let digest = try Self.sha256(of: staged)
                return (size, digest)
            }.value
            guard result.0 == Self.expectedBytes else {
                throw OfflineWhisperModelError.invalidSize
            }
            guard result.1 == Self.expectedSHA256 else {
                throw OfflineWhisperModelError.invalidChecksum
            }

            try? FileManager.default.removeItem(at: Self.modelURL)
            try FileManager.default.moveItem(at: staged, to: Self.modelURL)
            UserDefaults.standard.set(
                Self.expectedSHA256,
                forKey: "msm.offlineWhisper.verifiedSHA256"
            )
            let modified=try Self.modelURL.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
            UserDefaults.standard.set(modified,forKey:"msm.offlineWhisper.verifiedModifiedTime")
            downloadTask = nil
            status = .ready
            downloadedBytes = Self.expectedBytes
        } catch {
            try? FileManager.default.removeItem(at: staged)
            finishWithFailure(error.localizedDescription)
        }
    }

    private func finishWithFailure(_ message: String) {
        downloadTask = nil
        try? FileManager.default.removeItem(at: Self.partialURL)
        UserDefaults.standard.removeObject(forKey: "msm.offlineWhisper.verifiedSHA256")
        status = .failed(message)
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum OfflineWhisperModelError: LocalizedError {
    case invalidSize
    case invalidChecksum

    var errorDescription: String? {
        switch self {
        case .invalidSize:
            "Dung lượng model không đúng — file tải đã bị xóa."
        case .invalidChecksum:
            "Checksum model không khớp — file tải đã bị xóa để bảo vệ app."
        }
    }
}
