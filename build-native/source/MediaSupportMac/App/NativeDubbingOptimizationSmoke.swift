import AVFoundation
import Foundation

@MainActor
enum NativeDubbingOptimizationSmoke {
    private final class Speech: DubbingSpeechSynthesizing {
        var availableVoices: [DubbingVoiceDescriptor] { [] }
        var calls = 0
        var active = 0
        var peak = 0
        var delay: Duration = .milliseconds(20)

        func render(_ request: DubbingSpeechRequest) async throws {
            calls += 1
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(for: delay)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000,
                                       channels: 1, interleaved: true)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 12_000)!
            buffer.frameLength = 12_000
            for index in 0..<12_000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 0.1) * 0.1) }
            let file = try AVAudioFile(forWriting: request.outputURL, settings: format.settings)
            try file.write(from: buffer)
            file.close()
        }

        func stop() { }
    }

    static func run(directory: URL) async throws {
        let suite = "msm.dubbing.smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = DubbingCacheStore(rootURL: directory.appendingPathComponent("cache"))
        let speech = Speech()
        guard let session = DubbingSessionModel.optimizationSmokeSession(defaults: defaults, cache: cache, speech: speech)
        else { throw DubbingError.invalidAudioBuffer }
        func check(_ valid: Bool) throws { if !valid { throw DubbingError.invalidAudioBuffer } }
        func cue(_ id: Int, _ text: String) -> SRTSegment {
            .init(id: id, index: id, timing: "", startSeconds: Double(id), endSeconds: Double(id + 1), text: text)
        }
        func wait() async throws {
            for _ in 0..<1_000 {
                if !session.isRendering { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try check(!session.isRendering && session.errorMessage == nil)
        }
        session.speechProvider = .googleCloud
        let source = [cue(1, "Xin chào\nthế giới"), cue(2, "Xin chào thế giới"), cue(3, "Một câu khác")]
        session.synchronize(cues: source)
        session.renderAll(cues: source)
        try await wait()
        try check(speech.calls == 2 && speech.peak == 2 && session.renderedByCueID.count == 3)
        session.removeRenderedCues(cueIDs: [1, 2])
        session.renderAll(cues: source)
        try await wait()
        try check(speech.calls == 3 && session.renderedByCueID.count == 3)
        let reordered = [cue(11, "Xin chào thế giới"), cue(12, "Một câu khác")]
        session.synchronize(cues: reordered)
        session.renderAll(cues: reordered)
        try await wait()
        try check(speech.calls == 3 && session.renderedByCueID.count == 2)
        session.removeRenderedCues(cueIDs: [11])
        session.renderAll(cues: reordered)
        try await wait()
        try check(speech.calls == 4 && session.renderedByCueID.count == 2)
        speech.delay = .seconds(1)
        let interrupted = [cue(21, "Giọng sẽ được dừng"), cue(22, "Giọng dừng thứ hai")]
        session.synchronize(cues: interrupted)
        session.renderAll(cues: interrupted)
        try await Task.sleep(for: .milliseconds(30))
        session.cancelRendering()
        speech.delay = .milliseconds(20)
        let latest = [cue(31, "Tác vụ mới")]
        session.synchronize(cues: latest)
        session.renderAll(cues: latest)
        try await wait()
        try await Task.sleep(for: .milliseconds(80))
        try check(session.renderedByCueID.keys.sorted() == [31] && !session.isRendering && speech.active == 0)
        try check(session.progressCurrent == session.progressTotal)
        print("DUBBING_SMOKE_OK bounded=2 repeatedSpeech=deduplicated reflow=reused delete=regenerated cancellation=latest-preserved noAPI=true")
    }
}
