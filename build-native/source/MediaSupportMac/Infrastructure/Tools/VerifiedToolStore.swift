import Foundation

enum VerifiedToolStore {
    static var root:URL { AppPaths.runtimeRoot.appendingPathComponent("Tools",isDirectory:true) }
    static var publicKey:Data? {
        (Bundle.main.object(forInfoDictionaryKey:"MediaSupportToolUpdatePublicKey") as? String).flatMap { Data(base64Encoded:$0) }
    }
    static var appVersion:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0" }
    static func activeDirectory() throws -> URL? {
        guard let publicKey else { return nil }
        let record=root.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath:record.path) else { return nil }
        let manifest=try VerifiedToolManifest.verify(Data(contentsOf:record),publicKey:publicKey,appVersion:appVersion)
        let directory=root.appendingPathComponent(manifest.version,isDirectory:true)
        try manifest.validateFiles(in:directory)
        return directory
    }
    static func engineURL(bundled:URL) throws -> URL {
        if let directory=try? activeDirectory() {
            return directory.appendingPathComponent("offline-whisper/bin/whisper-cli")
        }
        return bundled
    }
    static func templateDirectory(bundled:URL) -> URL {
        if let directory=try? activeDirectory() {
            return directory.appendingPathComponent("MotionTemplates/Phu de nen den")
        }
        return bundled
    }
    /// Small metadata commit; keep one previous signed record. Runtime snapshots never point at staging.
    static func activate(envelope:Data,manifest:VerifiedToolManifest,stage:URL,root:URL) throws {
        try manifest.validateFiles(in:stage)
        let fm=FileManager.default, destination=root.appendingPathComponent(manifest.version,isDirectory:true)
        if fm.fileExists(atPath:destination.path) {
            try manifest.validateFiles(in:destination)
        } else { try fm.moveItem(at:stage,to:destination) }
        let active=root.appendingPathComponent("active.json")
        if fm.fileExists(atPath:active.path) {
            try Data(contentsOf:active).write(to:root.appendingPathComponent("previous.json"),options:.atomic)
        }
        try envelope.write(to:active,options:.atomic)
    }
    static func rollback(root:URL,publicKey:Data,appVersion:String) throws {
        let previous=root.appendingPathComponent("previous.json"),active=root.appendingPathComponent("active.json")
        if !FileManager.default.fileExists(atPath:previous.path) {
            if FileManager.default.fileExists(atPath:active.path) { try FileManager.default.removeItem(at:active) }
            return // Bundled engine/template remains the permanent fallback.
        }
        let data=try Data(contentsOf:previous)
        let manifest=try VerifiedToolManifest.verify(data,publicKey:publicKey,appVersion:appVersion)
        try manifest.validateFiles(in:root.appendingPathComponent(manifest.version))
        let current=try? Data(contentsOf:active)
        try data.write(to:active,options:.atomic)
        if let current { try current.write(to:previous,options:.atomic) }
    }
    static func prune(root:URL,publicKey:Data,appVersion:String) throws {
        var keep=Set<String>()
        for name in ["active.json","previous.json"] {
            let url=root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:url.path) {
                let manifest=try VerifiedToolManifest.verify(Data(contentsOf:url),publicKey:publicKey,appVersion:appVersion)
                keep.insert(manifest.version)
            }
        }
        for url in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) {
            let name=url.lastPathComponent,values=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            if !keep.contains(name),values.isDirectory==true,values.isSymbolicLink != true,
               name.range(of:#"^\d+(\.\d+){1,3}$"#,options:.regularExpression) != nil {
                try FileManager.default.removeItem(at:url)
            }
        }
    }
}
