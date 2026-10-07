import CryptoKit
import Foundation

struct VerifiedToolManifest: Codable, Sendable {
    struct File: Codable, Sendable {
        let path: String
        let url: URL
        let bytes: Int
        let sha256: String
    }
    let version: String
    let minimumAppVersion: String
    let architecture: String
    let files: [File]
    static let requiredPaths: Set<String> = ["offline-whisper/bin/whisper-cli",
        "MotionTemplates/Phu de nen den/Phu de nen den.moti",
        "MotionTemplates/Phu de nen den/large.png","MotionTemplates/Phu de nen den/small.png"]
    struct Envelope: Codable { let payload: Data; let signature: Data }

    static func verify(_ data: Data, publicKey: Data, appVersion: String) throws -> Self {
        guard data.count <= 64*1024 else { throw CocoaError(.fileReadCorruptFile) }
        let e=try JSONDecoder().decode(Envelope.self,from:data)
        let key=try Curve25519.Signing.PublicKey(rawRepresentation:publicKey)
        guard key.isValidSignature(e.signature,for:e.payload) else { throw CocoaError(.fileReadCorruptFile) }
        let manifest=try JSONDecoder().decode(Self.self,from:e.payload)
        guard manifest.version.range(of:#"^\d+(\.\d+){1,3}$"#,options:.regularExpression) != nil,
              manifest.version.count<=32,manifest.architecture=="arm64",
              manifest.minimumAppVersion.range(of:#"^\d+\.\d+\.\d+$"#,options:.regularExpression) != nil,
              appVersion.compare(manifest.minimumAppVersion,options:.numeric) != .orderedAscending,
              manifest.files.count==requiredPaths.count,Set(manifest.files.map(\.path))==requiredPaths else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for file in manifest.files {
            guard file.bytes>0,file.bytes<=16*1024*1024,
                  file.sha256.range(of:#"^[a-f0-9]{64}$"#,options:.regularExpression) != nil,
                  file.url.scheme=="https",file.url.host=="github.com",
                  file.url.path.hasPrefix("/Atu96/media-support-master/releases/download/"),
                  file.url.user==nil,file.url.password==nil,file.url.query==nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return manifest
    }
    static func sha256(_ url:URL) throws -> String {
        let handle=try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        var hash=SHA256()
        while let data=try handle.read(upToCount:65536),!data.isEmpty {
            try Task.checkCancellation()
            hash.update(data:data)
        }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    func validateFiles(in directory:URL) throws {
        for file in files {
            let path=directory.appendingPathComponent(file.path)
            let values=try path.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey])
            guard values.isSymbolicLink != true,values.fileSize==file.bytes,
                  try Self.sha256(path)==file.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        }
        let executable=directory.appendingPathComponent("offline-whisper/bin/whisper-cli")
        let handle=try FileHandle(forReadingFrom:executable)
        defer { try? handle.close() }
        guard try handle.read(upToCount:8)==Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
