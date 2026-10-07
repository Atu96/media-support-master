import AVFoundation
import Foundation

@MainActor
final class AppleSpeechDubbingService: NSObject, DubbingSpeechSynthesizing {
    private var activeSynthesizer: AVSpeechSynthesizer?
    private var activeSink: SpeechBufferSink?

    var availableVoices: [DubbingVoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { voice in
                DubbingVoiceDescriptor(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    qualityLabel: qualityLabel(for: voice.quality)
                )
            }
            .sorted {
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func render(_ request: DubbingSpeechRequest) async throws {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DubbingError.emptyText }

        let voice = request.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: request.localeIdentifier)
        guard let voice else { throw DubbingError.noVoice(request.localeIdentifier) }

        try? FileManager.default.removeItem(at: request.outputURL)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, request.rate))
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        for attempt in 0..<2 {
            do {
                try await renderAttempt(utterance, text: text, outputURL: request.outputURL)
                return
            } catch DubbingError.invalidAudioBuffer where attempt == 0 {
                try? FileManager.default.removeItem(at: request.outputURL)
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                try? FileManager.default.removeItem(at: request.outputURL)
                throw error
            }
        }
        throw DubbingError.invalidAudioBuffer
    }

    func stop() {
        activeSynthesizer?.stopSpeaking(at: .immediate)
        activeSink?.cancel(with: CancellationError())
        activeSynthesizer = nil
        activeSink = nil
    }

    private func renderAttempt(_ utterance: AVSpeechUtterance, text: String, outputURL: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        activeSynthesizer = synthesizer
        let sink = SpeechBufferSink(
            outputURL: outputURL,
            minimumDuration: DubbingAudioValidation.minimumPlausibleDuration(for: text)
        )
        activeSink = sink
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            synthesizer.stopSpeaking(at: .immediate)
            sink.cancel(with: DubbingError.speechTimedOut)
            if self?.activeSynthesizer === synthesizer { self?.activeSynthesizer = nil }
        }
        defer {
            timeoutTask.cancel()
            if activeSink === sink { activeSink = nil }
            if activeSynthesizer === synthesizer { activeSynthesizer = nil }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sink.install(continuation: continuation)
                synthesizer.write(utterance) { buffer in
                    sink.consume(buffer)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.activeSynthesizer?.stopSpeaking(at: .immediate)
                sink.cancel(with: CancellationError())
                self?.activeSynthesizer = nil
            }
        }
    }

    private func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }
}

private final class SpeechBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private let minimumDuration: Double
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false
    private var renderedDuration = 0.0

    init(outputURL: URL, minimumDuration: Double) {
        self.outputURL = outputURL
        self.minimumDuration = minimumDuration
    }

    func install(continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            finish(.failure(DubbingError.invalidAudioBuffer))
            return
        }
        if pcm.frameLength == 0 {
            finish(renderedDuration >= minimumDuration ? .success(()) : .failure(DubbingError.invalidAudioBuffer))
            return
        }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: outputURL, settings: pcm.format.settings)
            }
            try file?.write(from: pcm)
            if pcm.format.sampleRate > 0 {
                renderedDuration += Double(pcm.frameLength) / pcm.format.sampleRate
            }
        } catch {
            finish(.failure(error))
        }
    }

    func cancel(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        completed = true
        file = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
