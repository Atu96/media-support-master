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

    private final class BatchSpeech: DubbingSpeechBatchSynthesizing {
        let speech = Speech()
        var availableVoices: [DubbingVoiceDescriptor] { [] }
        var active = 0
        var peak = 0
        func render(_ request: DubbingSpeechRequest) async throws { try await speech.render(request) }
        var received: [DubbingSpeechRequest] = []
        func stop() { speech.stop() }
        func renderBatches(for requests: [DubbingSpeechRequest]) async throws -> [[DubbingSpeechRequest]] {
            stride(from: 0, to: requests.count, by: 2).map { Array(requests[$0..<min($0 + 2, requests.count)]) }
        }
        func renderBatch(_ requests: [DubbingSpeechRequest], progress: DubbingRenderProgressHandler?) async throws {
            received += requests
            active += 1; peak = max(peak, active)
            defer { active -= 1 }
            await progress?(.waiting(stage: .processing, elapsedSeconds: 0, timeoutSeconds: 300))
            try await Task.sleep(for: .milliseconds(30))
            for request in requests { try await speech.render(request) }
        }
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
        try check(session.effectiveRenderedCues.allSatisfy { abs($0.playedDuration - $0.cueDuration) < 0.001 })
        session.previewPlaybackRates([31: 2])
        session.commitPlaybackRateChanges(cueIDs: [31])
        try check(session.effectiveRenderedCue(cueID: 31)?.playbackRate == 2)
        session.fitPlaybackRateToSub(cueIDs: [31])
        try check(abs(session.effectiveRenderedCue(cueID: 31)!.playedDuration - 1) < 0.001)
        session.resetPlaybackRate(cueIDs: [31])
        try check(session.effectiveRenderedCue(cueID: 31)?.playbackRate == 1)

        let batchSpeech = BatchSpeech()
        let batchCache = DubbingCacheStore(rootURL: directory.appendingPathComponent("batch-cache"))
        guard let batchSession = DubbingSessionModel.optimizationSmokeSession(defaults: defaults, cache: batchCache, speech: batchSpeech)
        else { throw DubbingError.invalidAudioBuffer }
        batchSession.speechProvider = .maziao
        batchSession.maziaoDubbingStyle = .cues
        batchSession.maziaoVoiceIdentifier = "qa-voice"
        let batchCues = (1...9).map { cue($0, "Câu số \($0)") }
        batchSession.renderAll(cues: batchCues)
        for _ in 0..<1_000 {
            if !batchSession.isRendering { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try check(batchSession.errorMessage == nil && batchSession.renderedByCueID.count == 9
                  && batchSpeech.peak == 2 && batchSession.progressCurrent == 9)
        try check(batchSession.effectiveRenderedCues.allSatisfy { abs($0.playedDuration - $0.cueDuration) < 0.001 })
        try await paragraphSmoke(directory: directory, defaults: defaults)
        try await fitExportSmoke(directory: directory)
        print("DUBBING_SMOKE_OK bounded=2 maziaoBatches=2 autoFit=SUB manualRate=preserved natural1x=explicit refit=restored repeatedSpeech=deduplicated cancellation=latest-preserved noAPI=true")
    }

    private static func paragraphSmoke(directory: URL, defaults: UserDefaults) async throws {
        let speech = BatchSpeech()
        let cache = DubbingCacheStore(rootURL: directory.appendingPathComponent("paragraph-cache"))
        guard let session = DubbingSessionModel.optimizationSmokeSession(defaults: defaults, cache: cache, speech: speech) else { throw DubbingError.invalidAudioBuffer }
        session.speechProvider = .maziao; session.maziaoVoiceIdentifier = "qa-context-voice"
        session.maziaoDubbingStyle = .paragraphs
        func check(_ value: Bool) throws { if !value { throw DubbingError.invalidAudioBuffer } }
        func wait() async throws {
            for _ in 0..<1_000 {
                if !session.isRendering { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try check(!session.isRendering && session.errorMessage == nil)
        }
        let source = (1...6).map { id in
            let start = id <= 3 ? Double(id - 1) * 2 : 12 + Double(id - 4) * 2
            return SRTSegment(id: id, index: id, timing: SRTTimecode.makeTiming(start: start, end: start + 2),
                startSeconds: start, endSeconds: start + 2,
                text: "Sentence \(id) belongs to this connected paragraph.")
        }
        let groups = try MaziaoContextPlanner.groups(source, language: session.languageIdentifier)
        try check(groups.count == 2)
        session.renderSelected(cues: source, selectedIDs: [2])
        let shifted = source.map { cue in
            SRTSegment(id: cue.id, index: cue.index,
                timing: SRTTimecode.makeTiming(start: cue.startSeconds + 0.5, end: cue.endSeconds + 0.5),
                startSeconds: cue.startSeconds + 0.5, endSeconds: cue.endSeconds + 0.5, text: cue.text)
        }
        session.synchronize(cues: shifted)
        try await wait()
        try check(session.renderedByCueID.count == 1 && speech.received.count == 1
            && speech.received[0].text == groups[0].cue.text
            && speech.received[0].modelIdentifier == session.selectedModelIdentifier
            && session.effectiveRenderedCues[0].cueDuration == 6
            && session.effectiveRenderedCues[0].startSeconds == 0.5)
        session.previewPlaybackRates([1: 1.4]); session.commitPlaybackRateChanges(cueIDs: [1])
        session.renderAll(cues: source)
        try await wait()
        try check(session.renderedByCueID.count == 2 && speech.received.count == 2
            && session.effectiveRenderedCue(cueID: 1)?.playbackRate == 1.4)
        session.previewPlaybackRates([2: 1.1]); session.commitPlaybackRateChanges(cueIDs: [2])
        session.synchronize(cues: Array(source.suffix(3)))
        try await Task.sleep(for: .milliseconds(200))
        try check(session.renderedByCueID.count == 1 && session.effectiveRenderedCue(cueID: 1)?.playbackRate == 1.1)
        session.removeRenderedCues(cueIDs: [1]); session.synchronize(cues: Array(source.suffix(3)))
        try await Task.sleep(for: .milliseconds(100))
        try check(session.renderedByCueID.isEmpty)
        session.synchronize(cues: source)
        try await Task.sleep(for: .milliseconds(150))
        try check(session.renderedByCueID[2] == nil)
        session.renderAll(cues: source)
        session.cancelRendering()
        try await Task.sleep(for: .milliseconds(100))
        print("MAZIAO_CONTEXT_SMOKE_OK SUB=unchanged selected=wholeParagraph groups=2 providerModel=unmodified cache=isolated rate=preserved latestTiming=kept reindex=preserved deleted=kept cancellation=drained noAPI=true")
    }

    private static func fitExportSmoke(directory: URL) async throws {
        func tone(_ name: String, seconds: Double, silent: Bool = false) throws -> URL {
            let url = directory.appendingPathComponent(name + ".caf")
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: true)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let frames = Int(seconds * 24_000)
            var position = 0
            while position < frames {
                let count = min(4096, frames - position)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                for index in 0..<count {
                    let t = Double(position + index) / 24_000
                    let amplitude = silent ? 0 : (t > seconds * 0.75 ? 0.5 : 0.1)
                    buffer.floatChannelData![0][index] = Float(sin(t * 440 * 2 * .pi) * amplitude)
                }
                try file.write(from: buffer)
                position += count
            }
            file.close()
            return url
        }
        let source = try tone("fit-source", seconds: 4, silent: true)
        let long = try tone("fit-long", seconds: 2)
        let short = try tone("fit-short", seconds: 1)
        let cues = [
            DubbingRenderedCue(id: 1, startSeconds: 0, endSeconds: 1, audioDuration: 2, audioURL: long, fingerprint: "long"),
            DubbingRenderedCue(id: 2, startSeconds: 1, endSeconds: 3, audioDuration: 1, audioURL: short, fingerprint: "short")
        ]
        let output = directory.appendingPathComponent("fit-mix.m4a")
        var settings = DubbingMixSettings.default
        settings.originalVolume = 0
        try await DubbingMixExportService.export(mediaURL: source, renderedCues: cues, settings: settings, outputURL: output)
        let file = try AVAudioFile(forReading: output)
        for time in [0.88, 2.8] {
            file.framePosition = AVAudioFramePosition(time * file.processingFormat.sampleRate)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024)!
            try file.read(into: buffer, frameCount: 1024)
            let samples = buffer.floatChannelData![0]
            let rms = sqrt((0..<Int(buffer.frameLength)).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) } / Double(buffer.frameLength))
            guard rms > 0.15 else { throw DubbingError.invalidAudioBuffer }
        }
        file.close()
        let outside = DubbingRenderedCue(id: 3, startSeconds: 3.5, endSeconds: 5,
            audioDuration: 1, audioURL: short, fingerprint: "outside")
        do {
            try await DubbingMixExportService.export(mediaURL: source, renderedCues: [outside], settings: settings,
                outputURL: directory.appendingPathComponent("outside.m4a"))
            throw DubbingError.invalidAudioBuffer
        } catch DubbingError.audioOutsideMedia { }
        print("DUB_FIT_EXPORT_OK long=2x short=0.5x tailMarkers=retained outsideMedia=reported")
    }
}

/// Explicit TEST-only paid probe: fixed English samples, no personal subtitle input.
@MainActor
enum NativeMaziaoPipelineProbe {
    static func runContextContrast(directory: URL) async throws {
        let defaults = UserDefaults.standard
        let voice = (defaults.string(forKey: "msm.dubbing.maziaoVoice") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty else { print("MAZIAO_CONTEXT_PROBE_SKIPPED noConfiguredVoice=true"); return }
        _ = try await MaziaoAPIClient.accountDigest()
        let model = MaziaoDubbingModel(rawValue: defaults.string(forKey: "msm.dubbing.maziaoModel") ?? "") ?? .lingualV2
        let rate: Float = defaults.object(forKey: "msm.dubbing.rate") == nil ? 0.5 : defaults.float(forKey: "msm.dubbing.rate")
        let vietnamese = model == .vieten || model == .lingualV2
        let locale = vietnamese ? "vi-VN" : "en-US"
        let texts = vietnamese
            ? ["Xin chào các bạn.", "Hôm nay chúng ta cùng kiểm tra phần lồng tiếng.",
               "Các câu ngắn này thuộc một đoạn nói liền mạch.", "Hãy nghe giọng đọc có giữ ổn định từ đầu đến cuối không."]
            : ["Good morning, everyone.", "Today we will review our subtitle workflow.",
               "These short lines belong to one complete paragraph.", "Please listen for a steady voice from start to finish."]
        let context = texts.joined(separator: " ")
        let characters = context.count + texts.reduce(0) { $0 + $1.count }
        guard context.count > 100, characters <= 500 else { throw DubbingError.invalidAudioBuffer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paragraph = DubbingSpeechRequest(cueID: 100, text: context, localeIdentifier: locale, voiceIdentifier: voice,
            rate: rate, outputURL: directory.appendingPathComponent("paragraph.caf"), provider: .maziao, modelIdentifier: model.rawValue)
        let short = texts.enumerated().map { index, text in
            DubbingSpeechRequest(cueID: index + 1, text: text, localeIdentifier: locale, voiceIdentifier: voice,
                rate: rate, outputURL: directory.appendingPathComponent("short-\(index + 1).caf"), provider: .maziao, modelIdentifier: model.rawValue)
        }
        let service = MaziaoDubbingSpeechService(), started = Date()
        print("MAZIAO_CONTEXT_PROBE_START fixedCharacters=\(characters) language=\(locale) tasks=2 paragraph=1 shortParts=4")
        try await DubbingRenderQueue.run(count: 2, operation: { index in
            try await service.renderBatch(index == 0 ? [paragraph] : short) { progress in
                if case let .waiting(stage, elapsed, _) = progress, elapsed % 10 == 0 {
                    print("MAZIAO_CONTEXT_PROBE group=\(index + 1) stage=\(stage) elapsedSeconds=\(elapsed)")
                }
            }
        })
        let paragraphDuration = await DubbingCacheStore.audioDuration(at: paragraph.outputURL)
        guard DubbingAudioValidation.isPlausible(duration: paragraphDuration, text: context) else { throw DubbingError.invalidAudioBuffer }
        var clips: [DubbingAudioMergeClip] = [], offset = 0.0
        for request in short {
            let duration = await DubbingCacheStore.audioDuration(at: request.outputURL)
            guard DubbingAudioValidation.isPlausible(duration: duration, text: request.text) else { throw DubbingError.invalidAudioBuffer }
            clips.append(.init(audioURL: request.outputURL, startOffset: offset, playbackRate: 1))
            offset += duration + 0.2
        }
        _ = try await DubbingAudioMergeService.merge(clips: [.init(audioURL: paragraph.outputURL, startOffset: 0, playbackRate: 1)],
            outputURL: directory.appendingPathComponent("paragraph-natural.m4a"))
        _ = try await DubbingAudioMergeService.merge(clips: clips, outputURL: directory.appendingPathComponent("short-cues-natural.m4a"))
        print(String(format: "MAZIAO_CONTEXT_PROBE_OK files=5 paragraphSeconds=%.2f shortSeconds=%.2f totalSeconds=%.2f playback=1x quality=requiresListening",
            paragraphDuration, offset - 0.2, Date().timeIntervalSince(started)))
    }

    static func run(directory: URL) async throws {
        let defaults = UserDefaults.standard
        let voice = (defaults.string(forKey: "msm.dubbing.maziaoVoice") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty else {
            print("MAZIAO_PROBE_SKIPPED noConfiguredVoice=true")
            return
        }
        _ = try await MaziaoAPIClient.accountDigest()
        let model = MaziaoDubbingModel(rawValue: defaults.string(forKey: "msm.dubbing.maziaoModel") ?? "") ?? .lingualV2
        let rate: Float = defaults.object(forKey: "msm.dubbing.rate") == nil ? 0.5 : defaults.float(forKey: "msm.dubbing.rate")
        let texts = [
            "This is the first diagnostic sample for subtitle dubbing. We are checking that a complete sentence is generated and its audio file can be downloaded safely.",
            "Here is the second diagnostic sample for the same voice. Each segment should keep its own audio file so the editor can adjust playback timing independently.",
            "This third diagnostic sample belongs to another batch. We are measuring the normal queue and processing stages without sending any personal subtitle content.",
            "The final diagnostic sample checks the concurrent batch workflow. Successful audio must contain the whole sentence and remain available after local conversion."
        ]
        let characters = texts.reduce(0) { $0 + $1.count }
        guard characters < 700 else { throw DubbingError.invalidAudioBuffer }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let requests = texts.enumerated().map { index, text in
            DubbingSpeechRequest(cueID: index + 1, text: text, localeIdentifier: "en-US", voiceIdentifier: voice,
                rate: rate, outputURL: directory.appendingPathComponent("probe-\(index + 1).caf"),
                provider: .maziao, modelIdentifier: model.rawValue)
        }
        let service = MaziaoDubbingSpeechService()
        let clock = ContinuousClock()
        let started = clock.now
        var waitingGroups = Set<Int>()
        var peakWaiting = 0
        print("MAZIAO_PROBE_START fixedSampleCharacters=\(characters) batches=2 parts=4")
        try await DubbingRenderQueue.run(count: 2, operation: { batch in
            try await service.renderBatch(Array(requests[(batch * 2)..<(batch * 2 + 2)])) { progress in
                await MainActor.run {
                    switch progress {
                    case let .waiting(stage, elapsed, _):
                        waitingGroups.insert(batch); peakWaiting = max(peakWaiting, waitingGroups.count)
                        if elapsed % 10 == 0 { print("MAZIAO_PROBE group=\(batch + 1) stage=\(stage) elapsedSeconds=\(elapsed)") }
                    case .downloading: waitingGroups.remove(batch)
                    default: break
                    }
                }
            }
        })
        var durations: [Double] = []
        for request in requests {
            let duration = await DubbingCacheStore.audioDuration(at: request.outputURL)
            guard DubbingAudioValidation.isPlausible(duration: duration, text: request.text) else {
                throw DubbingError.invalidAudioBuffer
            }
            durations.append(duration)
        }
        let elapsed = started.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print(String(format: "MAZIAO_PROBE_OK files=4 peakRemoteWaiting=%d totalSeconds=%.2f durations=%@",
                     peakWaiting, seconds, durations.map { String(format: "%.2f", $0) }.joined(separator: ",")))
    }
}
