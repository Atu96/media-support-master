import Foundation

enum MotionTemplateInstaller {
    static let folderName = "Phu de nen den"
    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/Motion Templates.localized/Titles.localized/\(folderName)/\(folderName).moti")
    }
    static var bundledDirectory: URL? {
        guard let bundled=Bundle.main.resourceURL?.appendingPathComponent("MotionTemplates/\(folderName)") else { return nil }
        return VerifiedToolStore.templateDirectory(bundled:bundled)
    }
    static func resolveOrInstall() throws -> URL {
        let fm = FileManager.default
        let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.apple.FinalCut/Data/Movies/Motion Templates.localized/Titles.localized/\(folderName)/\(folderName).moti")
        for url in [installedURL, legacy] where fm.isReadableFile(atPath: url.path) { return url }
        guard let bundledDirectory else { throw CocoaError(.fileNoSuchFile) }
        return try install(source: bundledDirectory, destination: installedURL.deletingLastPathComponent())
    }
    /// Preserve an existing template, including user edits. Publish only a complete directory.
    static func install(source: URL, destination: URL) throws -> URL {
        let fm = FileManager.default
        let file = destination.appendingPathComponent("\(folderName).moti")
        if fm.isReadableFile(atPath: file.path) { return file }
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let sourceFile = source.appendingPathComponent("\(folderName).moti")
        _ = try XMLDocument(contentsOf: sourceFile, options: [])
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".msm-template-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: source, to: stage)
        try Task.checkCancellation()
        try fm.moveItem(at: stage, to: destination)
        return file
    }
}
