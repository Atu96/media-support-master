import Foundation

/// Explicit TEST-only CLI smoke. Uses a caller-supplied synthetic recording, no providers or UI.
@MainActor
enum NativeIntegratedToolsSmoke {
    static func run(directory:URL) async throws {
        let media=directory.appendingPathComponent("speech.wav")
        let script=directory.appendingPathComponent("script.txt")
        guard FileManager.default.fileExists(atPath:media.path),FileManager.default.fileExists(atPath:script.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let output=directory.appendingPathComponent("aligned.srt")
        try await NativeScriptAlignmentService.align(media:media,scriptFile:script,output:output,language:"en") { print($0) }
        let original=try String(contentsOf:script,encoding:.utf8)
        let result=try String(contentsOf:output,encoding:.utf8)
        let segments=SRTDocument.parseSegments(result)
        guard !segments.isEmpty,original.filter({ !$0.isWhitespace })==segments.map(\.text).joined().filter({ !$0.isWhitespace }) else {
            throw NativeScriptAlignmentError.insufficientEvidence
        }
        let language=try await NativeWhisperRuntime.detectLanguage(media:media) { print($0) }
        guard language.language=="en" else { throw NativeScriptAlignmentError.insufficientEvidence }
        let xml=try NativeFCPXMLExporter.render(segments:segments,name:"synthetic-smoke",style:SubtitleBurnStyle(),
                                               templateURL:MotionTemplateInstaller.resolveOrInstall())
        try xml.write(to:directory.appendingPathComponent("aligned.fcpxml"),atomically:true,encoding:.utf8)
        print("NATIVE_SMOKE_OK language=\(language.language) cues=\(segments.count) originalText=preserved")
    }
}
