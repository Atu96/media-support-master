import Foundation

/// Original Japanese MeCab algorithm packaged with its pinned runtime/dictionary.
enum JapaneseScriptAlignmentService {
    static var helperURL:URL? { Bundle.main.resourceURL?.appendingPathComponent("JapaneseTools/japanese-helper") }
    static func align(media:URL,scriptFile:URL,output:URL,progress:@escaping @Sendable(String)->Void) async throws {
        guard let helper=helperURL,FileManager.default.isExecutableFile(atPath:helper.path) else {
            throw OfflineWhisperError.engineMissing
        }
        progress("MSM_PROGRESS:2")
        let model=try await OfflineWhisperModelManager.ensureAvailableModel()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("msm-japanese-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let audio=directory.appendingPathComponent("audio.wav"),base=directory.appendingPathComponent("whisper")
        progress("… Chuẩn bị âm thanh cho tiếng Nhật")
        try await NativeAudioPreparation.extract(media:media,output:audio)
        var args=["-m",model.path,"-f",audio.path,"--language","ja","--max-len","1",
                  "--output-srt","--output-file",base.path,"--print-progress","--threads","4"]
        if UserDefaults.standard.bool(forKey:"msm.whisper.cpuOnly") { args.append("--no-gpu") }
        _=try await NativeWhisperProcess.run(executable:NativeWhisperRuntime.engineURL(),arguments:args) { line in
            if line.hasPrefix("MSM_PROGRESS:"),let n=Int(line.dropFirst("MSM_PROGRESS:".count)) {
                progress("MSM_PROGRESS:\(min(75,n*75/90))")
            } else { progress(line) }
        }
        progress("MSM_PROGRESS:80")
        progress("… Khớp kịch bản Nhật bằng MeCab")
        _=try await NativeWhisperProcess.run(executable:helper,arguments:[base.appendingPathExtension("srt").path,scriptFile.path,output.path],timeout:300,progress:{_ in})
        try Task.checkCancellation()
        guard !(try SRTDocument.parseSegments(String(contentsOf:output,encoding:.utf8))).isEmpty else {
            throw OfflineWhisperError.noTranscript
        }
        progress("MSM_PROGRESS:100")
    }
}
