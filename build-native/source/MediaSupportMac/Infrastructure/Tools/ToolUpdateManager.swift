import Foundation

@MainActor
final class ToolUpdateManager: ObservableObject {
    static let shared=ToolUpdateManager()
    static let feed=URL(string:"https://raw.githubusercontent.com/Atu96/media-support-master/main/updates/tools.json")!
    @Published private(set) var busy=false
    @Published private(set) var message="Công cụ tích hợp đã sẵn sàng"
    private let session:URLSession = {
        let c=URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=180
        return URLSession(configuration:c)
    }()
    func checkIfDue() async {
        guard UserDefaults.standard.object(forKey:"msm.tools.autoUpdate") as? Bool ?? true,
              Date().timeIntervalSince1970-UserDefaults.standard.double(forKey:"msm.tools.lastCheck")>86400 else { return }
        await update()
    }
    func update() async {
        guard !busy,!MediaEngineService.shared.isRunning else { message="Chờ tác vụ hiện tại hoàn tất";return }
        guard let key=VerifiedToolStore.publicKey else { message="Chưa thiết lập nguồn cập nhật công cụ";return }
        busy=true;defer { busy=false }
        UserDefaults.standard.set(Date().timeIntervalSince1970,forKey:"msm.tools.lastCheck")
        message="Đang kiểm tra cập nhật công cụ…"
        do {
            let (data,response)=try await session.data(from:Self.feed)
            guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
            let manifest=try VerifiedToolManifest.verify(data,publicKey:key,appVersion:VerifiedToolStore.appVersion)
            let bundled=Bundle.main.object(forInfoDictionaryKey:"MediaSupportToolVersion") as? String ?? "0.0"
            let active=try? Data(contentsOf:VerifiedToolStore.root.appendingPathComponent("active.json"))
            let activeManifest=active.flatMap { try? VerifiedToolManifest.verify($0,publicKey:key,appVersion:VerifiedToolStore.appVersion) }
            let current=activeManifest?.version ?? bundled
            UserDefaults.standard.set(Date().timeIntervalSince1970,forKey:"msm.tools.lastCheck")
            guard manifest.version.compare(current,options:.numeric) == .orderedDescending else { message="Công cụ đang ở phiên bản mới nhất";return }
            let fm=FileManager.default,root=VerifiedToolStore.root
            try fm.createDirectory(at:root,withIntermediateDirectories:true)
            let stage=root.appendingPathComponent(".download-\(UUID().uuidString)")
            try fm.createDirectory(at:stage,withIntermediateDirectories:true)
            defer { try? fm.removeItem(at:stage) }
            message="Đang tải công cụ…"
            for file in manifest.files {
                let (download,response)=try await session.download(from:file.url)
                guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
                let destination=stage.appendingPathComponent(file.path)
                try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
                try fm.moveItem(at:download,to:destination)
                try fm.setAttributes([.posixPermissions:file.path.hasSuffix("whisper-cli") ? 0o755 : 0o644],ofItemAtPath:destination.path)
            }
            message="Đang xác minh công cụ…"
            let validation=Task.detached(priority:.utility) { try manifest.validateFiles(in:stage) }
            try await withTaskCancellationHandler { try await validation.value } onCancel: { validation.cancel() }
            let executable=stage.appendingPathComponent("offline-whisper/bin/whisper-cli")
            _ = try await NativeWhisperProcess.run(executable:executable,arguments:["--help"],timeout:15,progress:{ _ in })
            _ = try XMLDocument(contentsOf:stage.appendingPathComponent("MotionTemplates/Phu de nen den/Phu de nen den.moti"),options:[])
            guard !MediaEngineService.shared.isRunning else { message="Chờ tác vụ hiện tại hoàn tất";return }
            try VerifiedToolStore.activate(envelope:data,manifest:manifest,stage:stage,root:root)
            let cleanup=Task.detached(priority:.utility) {
                try? VerifiedToolStore.prune(root:root,publicKey:key,appVersion:VerifiedToolStore.appVersion)
            }
            _ = await cleanup.value
            message="Đã cập nhật công cụ"
        } catch {
            // Failed downloads/signatures never replace the active or bundled tools.
            message="Không thể cập nhật; vẫn dùng công cụ hiện tại"
        }
    }
    func rollback() {
        guard !busy,!MediaEngineService.shared.isRunning,let key=VerifiedToolStore.publicKey else { return }
        do { try VerifiedToolStore.rollback(root:VerifiedToolStore.root,publicKey:key,appVersion:VerifiedToolStore.appVersion)
            message="Đã phục hồi công cụ trước đó"
        } catch { message="Không thể phục hồi công cụ" }
    }
}
