import Foundation

enum NativeScriptAlignmentService {
    static func align(media:URL, scriptFile:URL, output:URL, language:String,
                      progress:@escaping @Sendable (String)->Void) async throws {
        let script=try String(contentsOf:scriptFile,encoding:.utf8)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("msm-align-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let transcript=try await NativeWhisperRuntime.transcript(media:media,language:language,directory:directory,progress:progress)
        progress("MSM_PROGRESS:92")
        progress("… Khớp văn bản gốc với mốc lời nói")
        let worker=Task.detached(priority:.userInitiated) {
            let words=try NativeScriptAligner.align(script:script,tokens:transcript.tokens,language:language)
            let cues=SpeechWordTimingProcessor.makeSegments(from:words,languageCode:language)
            func compact(_ text:String)->String { text.filter { !$0.isWhitespace } }
            guard !cues.isEmpty,compact(cues.map(\.text).joined())==compact(script) else {
                throw NativeScriptAlignmentError.insufficientEvidence
            }
            return SRTDocument.renderSRT(cues)
        }
        let text=try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        try text.write(to:output,atomically:true,encoding:.utf8)
        progress("MSM_PROGRESS:100")
    }
}
