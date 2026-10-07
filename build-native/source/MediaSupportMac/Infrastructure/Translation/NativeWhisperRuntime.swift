@preconcurrency import AVFoundation
import Foundation

enum NativeWhisperRuntime {
    static func transcript(media: URL, language: String, directory: URL,
                           progress: @escaping @Sendable (String) -> Void) async throws -> WhisperTimestampTranscript {
        progress("MSM_PROGRESS:2")
        progress("… Kiểm tra model Whisper trên máy")
        let model = try await OfflineWhisperModelManager.ensureAvailableModel()
        let wav=directory.appendingPathComponent("audio.wav")
        progress("… Chuẩn bị âm thanh")
        try await NativeAudioPreparation.extract(media:media,output:wav)
        let seconds=Double(try AVAudioFile(forReading:wav).length)/16000
        let output=directory.appendingPathComponent("transcript")
        var args=["-m",model.path,"-f",wav.path,"-l",language,"-ojf","-of",output.path,
                  "--threads",String(min(4,ProcessInfo.processInfo.activeProcessorCount)),"--print-progress"]
        // Short samples avoid first-use Metal compilation cost; long jobs amortize it.
        let cpuOnly=UserDefaults.standard.bool(forKey:"msm.whisper.cpuOnly") || seconds < 30
        if cpuOnly { args.append("--no-gpu") }
        progress("MSM_PROGRESS:15")
        progress("… Whisper đang lấy mốc lời nói")
        let engine=try engineURL()
        _ = try await NativeWhisperProcess.run(executable:engine,arguments:args,progress:progress)
        let data=try Data(contentsOf:output.appendingPathExtension("json"))
        guard data.count <= 64*1024*1024 else { throw NativeScriptAlignmentError.tooLarge }
        return try WhisperTimestampDecoder.decode(data)
    }
    static func detectLanguage(media: URL, progress: @escaping @Sendable (String) -> Void) async throws -> MediaLanguageRecord {
        progress("… Kiểm tra model Whisper trên máy")
        let model=try await OfflineWhisperModelManager.ensureAvailableModel()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("msm-detect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let duration=try await AVURLAsset(url:media).load(.duration).seconds
        guard duration.isFinite,duration > 0 else { throw OfflineWhisperError.noAudio }
        // At most two short windows. Silence does not become a language guess.
        for offset in [0.0,max(0,duration/2-10)] {
            try Task.checkCancellation()
            let wav=directory.appendingPathComponent("sample-\(Int(offset)).wav")
            progress("… Đọc đoạn âm thanh ngắn")
            try await NativeAudioPreparation.extract(media:media,output:wav,range:CMTimeRange(
                start:CMTime(seconds:offset,preferredTimescale:600),
                duration:CMTime(seconds:min(20,duration-offset),preferredTimescale:600)))
            let rms=try await Task.detached(priority:.utility) { try rms(of:wav) }.value
            if rms < 0.0003 { continue }
            progress("… Đang nhận diện ngôn ngữ")
            let log=try await NativeWhisperProcess.run(executable:engineURL(),arguments:[
                "-m",model.path,"-f",wav.path,"--detect-language","--no-gpu","--threads","4"],timeout:120,progress:progress)
            if let result=try? WhisperTimestampDecoder.language(from:log) {
                return MediaLanguageRecord(language:result.code,confidence:result.confidence,detector:"whisper-bundled",
                    media:media.path,detectedAt:ISO8601DateFormatter().string(from:Date()))
            }
        }
        throw NativeScriptAlignmentError.insufficientEvidence
    }
    static func engineURL() throws -> URL {
        guard let bundled=Bundle.main.resourceURL?.appendingPathComponent("offline-whisper/bin/whisper-cli") else {
            throw OfflineWhisperError.engineMissing
        }
        let selected=try VerifiedToolStore.engineURL(bundled:bundled)
        guard FileManager.default.isExecutableFile(atPath:selected.path) else { throw OfflineWhisperError.engineMissing }
        return selected
    }
    private static func rms(of url:URL) throws -> Double {
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:16384),let channel=buffer.floatChannelData else {
            throw OfflineWhisperError.cannotPrepareAudio
        }
        var sum=0.0,count=0
        while file.framePosition<file.length {
            try Task.checkCancellation()
            try file.read(into:buffer,frameCount:AVAudioFrameCount(min(16384,file.length-file.framePosition)))
            for i in 0..<Int(buffer.frameLength) { let x=Double(channel[0][i]);sum += x*x;count += 1 }
        }
        return sqrt(sum/Double(max(1,count)))
    }
}
