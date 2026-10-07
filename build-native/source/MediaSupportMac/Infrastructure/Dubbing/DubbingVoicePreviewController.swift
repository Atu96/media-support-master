import AVFoundation
import Foundation

@MainActor
final class DubbingVoicePreviewController: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var isPlaying = false
    @Published private(set) var activeProvider: DubbingSpeechProvider?
    @Published private(set) var errorMessage = ""

    private let appleSpeech: DubbingSpeechSynthesizing
    private var player: AVAudioPlayer?
    private var playbackData: Data?
    private var stopTask: Task<Void, Never>?
    private var temporaryURL: URL?
    private var requestToken: UInt = 0

    init(
        appleSpeech: DubbingSpeechSynthesizing? = nil
    ) {
        self.appleSpeech = appleSpeech ?? AppleSpeechDubbingService()
    }

    func play(_ request: DubbingSpeechRequest) async {
        stop()
        let token = requestToken
        activeProvider = request.provider
        isBusy = true
        errorMessage = ""
        var preparedURL: URL?

        do {
            let audioURL: URL
            switch request.provider {
            case .googleCloud, .maziao, .elevenLabs:
                throw DubbingError.providerResponse(
                    L10n.string("Giọng online được nghe trên trang mẫu chính thức của nhà cung cấp.")
                )
            case .appleOffline:
                audioURL = makeTemporaryURL(extension: "caf")
                preparedURL = audioURL
                let outputRequest = DubbingSpeechRequest(
                    cueID: request.cueID,
                    text: request.text,
                    localeIdentifier: request.localeIdentifier,
                    voiceIdentifier: request.voiceIdentifier,
                    rate: request.rate,
                    outputURL: audioURL,
                    provider: request.provider,
                    modelIdentifier: request.modelIdentifier
                )
                try await appleSpeech.render(outputRequest)
            }
            preparedURL = audioURL

            try Task.checkCancellation()
            guard token == requestToken else {
                try? FileManager.default.removeItem(at: audioURL)
                return
            }
            removeTemporaryFile()
            temporaryURL = audioURL
            let prepared = try DubbingPreviewAudioLoader.prepare(from: audioURL)
            let player = prepared.player
            let duration = player.duration
            guard token == requestToken else {
                removeTemporaryFile()
                return
            }
            guard duration.isFinite, duration > 0 else { throw DubbingError.invalidAudioBuffer }
            self.player = player
            playbackData = prepared.data
            isBusy = false
            guard player.play() else { throw DubbingError.invalidAudioBuffer }
            isPlaying = true

            stopTask = Task { @MainActor [weak self, weak player] in
                try? await Task.sleep(for: .seconds(duration + 0.2))
                guard !Task.isCancelled else { return }
                player?.pause()
                guard self?.player === player else { return }
                self?.finishPlayback()
            }
        } catch is CancellationError {
            guard token == requestToken else {
                if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
                return
            }
            finishPlayback()
        } catch {
            guard token == requestToken else {
                if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
                return
            }
            isBusy = false
            isPlaying = false
            errorMessage = error.localizedDescription
            removeTemporaryFile()
            if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
        }
    }

    func stop() {
        requestToken &+= 1
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
        player = nil
        playbackData = nil
        appleSpeech.stop()
        isBusy = false
        isPlaying = false
        activeProvider = nil
        errorMessage = ""
        removeTemporaryFile()
    }

    private func makeTemporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-voice-preview-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private func finishPlayback() {
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
        player = nil
        playbackData = nil
        isBusy = false
        isPlaying = false
        activeProvider = nil
        removeTemporaryFile()
    }

    private func removeTemporaryFile() {
        guard let temporaryURL else { return }
        try? FileManager.default.removeItem(at: temporaryURL)
        self.temporaryURL = nil
    }
}
