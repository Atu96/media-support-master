import AppKit
import Foundation

@MainActor
final class DubbingSessionModel: ObservableObject {
    static let shared = DubbingSessionModel()

    static func optimizationSmokeSession(defaults: UserDefaults, cache: DubbingCacheStore,
                                         speech: DubbingSpeechSynthesizing) -> DubbingSessionModel? {
        guard Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test" else { return nil }
        return DubbingSessionModel(defaults: defaults, cache: cache, speech: speech, googleSpeech: speech,
                                   elevenSpeech: speech, maziaoSpeech: speech, readCredentials: false)
    }

    @Published private(set) var renderedByCueID: [Int: DubbingRenderedCue] = [:]
    @Published private(set) var playbackRateByFingerprint: [String: Double] = [:]
    @Published private(set) var renderingCueIDs: Set<Int> = []
    @Published private(set) var progressCurrent = 0
    @Published private(set) var progressTotal = 0
    @Published private(set) var isExporting = false
    @Published private(set) var hasGoogleCredential = false
    @Published private(set) var hasElevenLabsCredential = false
    @Published private(set) var hasMaziaoCredential = false
    @Published private(set) var googleVoices: [DubbingCloudVoice] = []
    @Published private(set) var maziaoVoices: [MaziaoVoiceDescriptor] = []
    @Published private(set) var elevenVoices: [DubbingCloudVoice] = []
    @Published private(set) var isRefreshingGoogleVoices = false
    @Published private(set) var isRefreshingMaziaoVoices = false
    @Published private(set) var isRefreshingElevenVoices = false
    @Published private(set) var googleVoiceCatalogError = ""
    @Published private(set) var maziaoVoiceCatalogError = ""
    @Published private(set) var elevenVoiceCatalogError = ""
    @Published private(set) var cacheUsage: DubbingCacheUsage = .empty
    @Published var statusMessage = ""
    @Published var errorMessage: String?

    @Published var speechProvider: DubbingSpeechProvider {
        didSet { defaults.set(speechProvider.rawValue, forKey: Keys.provider) }
    }
    @Published var googleModel: GoogleDubbingModel {
        didSet {
            defaults.set(googleModel.rawValue, forKey: Keys.googleModel)
            selectCompatibleGoogleVoiceIfNeeded()
        }
    }
    @Published var googleVoiceIdentifier: String {
        didSet { defaults.set(googleVoiceIdentifier, forKey: Keys.googleVoice) }
    }
    @Published var elevenModel: ElevenLabsDubbingModel {
        didSet { defaults.set(elevenModel.rawValue, forKey: Keys.elevenModel) }
    }
    @Published var elevenVoiceIdentifier: String {
        didSet { defaults.set(elevenVoiceIdentifier, forKey: Keys.elevenVoice) }
    }
    @Published var maziaoModel: MaziaoDubbingModel {
        didSet { defaults.set(maziaoModel.rawValue, forKey: Keys.maziaoModel) }
    }
    @Published var maziaoVoiceIdentifier: String {
        didSet { defaults.set(maziaoVoiceIdentifier, forKey: Keys.maziaoVoice) }
    }

    @Published var languageIdentifier: String {
        didSet {
            defaults.set(languageIdentifier, forKey: Keys.language)
            selectCompatibleVoiceIfNeeded()
        }
    }
    @Published var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voice) }
    }
    @Published var speechRate: Float {
        didSet { defaults.set(speechRate, forKey: Keys.rate) }
    }
    @Published var originalVolume: Float {
        didSet { defaults.set(originalVolume, forKey: Keys.originalVolume) }
    }
    @Published var dubVolume: Float {
        didSet { defaults.set(dubVolume, forKey: Keys.dubVolume) }
    }
    @Published var duckOriginal: Bool {
        didSet { defaults.set(duckOriginal, forKey: Keys.duckOriginal) }
    }

    private enum Keys {
        static let provider = "msm.dubbing.provider"
        static let googleModel = "msm.dubbing.googleModel"
        static let googleVoice = "msm.dubbing.googleVoice"
        static let elevenModel = "msm.dubbing.elevenModel"
        static let elevenVoice = "msm.dubbing.elevenVoice"
        static let maziaoModel = "msm.dubbing.maziaoModel"
        static let maziaoVoice = "msm.dubbing.maziaoVoice"
        static let language = "msm.dubbing.language"
        static let voice = "msm.dubbing.voice"
        static let rate = "msm.dubbing.rate"
        static let originalVolume = "msm.dubbing.originalVolume"
        static let dubVolume = "msm.dubbing.dubVolume"
        static let duckOriginal = "msm.dubbing.duckOriginal"
        static let playbackRates = "msm.dubbing.playbackRates"
    }

    private let defaults: UserDefaults
    private let cache: DubbingCacheStore
    private let appleSpeech: DubbingSpeechSynthesizing
    private let googleSpeech: DubbingSpeechSynthesizing
    private let elevenSpeech: DubbingSpeechSynthesizing
    private let maziaoSpeech: DubbingSpeechSynthesizing
    private let playback = DubbingPlaybackCoordinator()
    private var renderTask: Task<Void, Never>?
    private var renderGeneration: UUID?
    private var cacheLoadTask: Task<Void, Never>?
    private var mergeAudioTask: Task<Void, Never>?
    private var mergeAudioGeneration: UUID?
    private var cacheUsageGeneration: UUID?
    private var activeFingerprintByCueID: [Int: String] = [:]

    var voices: [DubbingVoiceDescriptor] { appleSpeech.availableVoices }

    var languageIdentifiers: [String] {
        let preferred = ["vi-VN", "en-US", "zh-CN", "ja-JP", "ko-KR"]
        let all = Set(voices.map(\.language))
        return preferred.filter(all.contains) + all.subtracting(preferred).sorted()
    }

    var voicesForSelectedLanguage: [DubbingVoiceDescriptor] {
        voices.filter { $0.language.caseInsensitiveCompare(languageIdentifier) == .orderedSame }
    }

    var googleVoicesForSelectedModel: [DubbingCloudVoice] {
        let source = googleVoices.isEmpty ? googleModel.voices : googleVoices
        return source.filter { googleModel.matches(voiceIdentifier: $0.id) }
    }

    var maziaoVoicesForSelectedModel: [MaziaoVoiceDescriptor] {
        maziaoVoices.filter { $0.modelID == nil || $0.modelID == maziaoModel.rawValue }
    }

    var isRendering: Bool { !renderingCueIDs.isEmpty }

    private init(
        defaults: UserDefaults = .standard,
        cache: DubbingCacheStore = DubbingCacheStore(),
        speech: DubbingSpeechSynthesizing? = nil,
        googleSpeech: DubbingSpeechSynthesizing? = nil,
        elevenSpeech: DubbingSpeechSynthesizing? = nil,
        maziaoSpeech: DubbingSpeechSynthesizing? = nil,
        readCredentials: Bool = true
    ) {
        self.defaults = defaults
        self.cache = cache
        appleSpeech = speech ?? AppleSpeechDubbingService()
        self.googleSpeech = googleSpeech ?? GoogleCloudDubbingService()
        self.elevenSpeech = elevenSpeech ?? ElevenLabsDubbingService()
        self.maziaoSpeech = maziaoSpeech ?? MaziaoDubbingSpeechService()

        speechProvider = DubbingSpeechProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .googleCloud
        googleModel = GoogleDubbingModel(rawValue: defaults.string(forKey: Keys.googleModel) ?? "") ?? .chirp3HD
        googleVoiceIdentifier = defaults.string(forKey: Keys.googleVoice) ?? "vi-VN-Chirp3-HD-Leda"
        elevenModel = ElevenLabsDubbingModel(rawValue: defaults.string(forKey: Keys.elevenModel) ?? "") ?? .v3
        elevenVoiceIdentifier = defaults.string(forKey: Keys.elevenVoice) ?? ""
        maziaoModel = MaziaoDubbingModel(rawValue: defaults.string(forKey: Keys.maziaoModel) ?? "") ?? .lingualV2
        maziaoVoiceIdentifier = defaults.string(forKey: Keys.maziaoVoice) ?? ""

        let savedLanguage = defaults.string(forKey: Keys.language) ?? "vi-VN"
        languageIdentifier = savedLanguage
        voiceIdentifier = defaults.string(forKey: Keys.voice) ?? ""
        let savedRate = defaults.object(forKey: Keys.rate) == nil ? 0.5 : defaults.float(forKey: Keys.rate)
        speechRate = min(0.62, max(0.38, savedRate))
        originalVolume = defaults.object(forKey: Keys.originalVolume) == nil ? 1 : defaults.float(forKey: Keys.originalVolume)
        dubVolume = defaults.object(forKey: Keys.dubVolume) == nil ? 1 : defaults.float(forKey: Keys.dubVolume)
        duckOriginal = defaults.object(forKey: Keys.duckOriginal) == nil ? true : defaults.bool(forKey: Keys.duckOriginal)
        playbackRateByFingerprint = defaults.dictionary(forKey: Keys.playbackRates)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
        selectCompatibleGoogleVoiceIfNeeded()
        selectCompatibleVoiceIfNeeded()
        hasGoogleCredential = readCredentials && GoogleTTSCredentialStore.hasKey
        hasElevenLabsCredential = readCredentials && ElevenLabsCredentialStore.hasKey
        hasMaziaoCredential = readCredentials && MaziaoCredentialStore.hasKey
        refreshCacheUsage()
    }

    func synchronize(cues: [SRTSegment]) {
        guard AppFeatureFlags.dubbingEnabled else { return }
        let cueIDs = Set(cues.map(\.id))
        var current = renderedByCueID.filter { cueIDs.contains($0.key) }

        cacheLoadTask?.cancel()
        let language = languageIdentifier
        let provider = speechProvider
        let model = selectedModelIdentifier
        let voice = selectedVoiceIdentifier
        let rate = speechRate
        let fingerprints = Dictionary(uniqueKeysWithValues: cues.map { cue in
            (
                cue.id,
                DubbingFingerprint.make(
                    cue: cue,
                    localeIdentifier: language,
                    voiceIdentifier: voice,
                    rate: rate,
                    provider: provider,
                    modelIdentifier: model
                )
            )
        })
        activeFingerprintByCueID = fingerprints
        for cue in cues {
            guard let fingerprint = fingerprints[cue.id] else { continue }
            if let rendered = current[cue.id], rendered.fingerprint == fingerprint {
                current[cue.id] = rendered.updatingTiming(from: cue)
            } else {
                current.removeValue(forKey: cue.id)
            }
        }
        renderedByCueID = current
        cacheLoadTask = Task { [weak self] in
            guard let self else { return }
            var loaded = self.renderedByCueID
            for cue in cues {
                guard !Task.isCancelled else { return }
                guard let fingerprint = fingerprints[cue.id] else { continue }
                if let rendered = loaded[cue.id], rendered.fingerprint == fingerprint {
                    loaded[cue.id] = rendered.updatingTiming(from: cue)
                    continue
                }
                let url = self.cachedClip(cue: cue, language: language, voice: voice,
                                          rate: rate, provider: provider, model: model)
                guard let url else {
                    loaded.removeValue(forKey: cue.id)
                    continue
                }
                let duration = await DubbingCacheStore.audioDuration(at: url)
                guard DubbingAudioValidation.isPlausible(duration: duration, text: cue.text) else {
                    self.cache.removeClip(for: fingerprint)
                    loaded.removeValue(forKey: cue.id)
                    continue
                }
                loaded[cue.id] = DubbingRenderedCue(
                    id: cue.id,
                    startSeconds: cue.startSeconds,
                    endSeconds: cue.endSeconds,
                    audioDuration: duration,
                    audioURL: url,
                    fingerprint: fingerprint
                )
            }
            guard !Task.isCancelled else { return }
            guard self.activeFingerprintByCueID == fingerprints else { return }
            // Render completions may arrive while asset durations are loading.
            for (id, rendered) in self.renderedByCueID where rendered.fingerprint == fingerprints[id] {
                loaded[id] = rendered
            }
            self.renderedByCueID = loaded
            self.refreshCacheUsage()
        }
    }

    /// Preserves DUB clips across subtitle reindexing and builds one local clip
    /// for the merged cue when every source cue already has valid audio.
    func preserveRenderedAudioAfterMerge(
        previousCues: [SRTSegment],
        updatedCues: [SRTSegment],
        mergedSourceIDs: Set<Int>
    ) {
        guard AppFeatureFlags.dubbingEnabled,
              let plan = DubbingMergePreservationPlan.make(
                previousCues: previousCues,
                updatedCues: updatedCues,
                mergedSourceIDs: mergedSourceIDs
              ) else { return }

        cacheLoadTask?.cancel()
        mergeAudioTask?.cancel()
        playback.stopAll(restoreOriginalVolume: originalVolume)

        let language = languageIdentifier
        let provider = speechProvider
        let model = selectedModelIdentifier
        let voice = selectedVoiceIdentifier
        let rate = speechRate
        let previousRendered = renderedByCueID
        func fingerprint(for cue: SRTSegment) -> String {
            DubbingFingerprint.make(
                cue: cue,
                localeIdentifier: language,
                voiceIdentifier: voice,
                rate: rate,
                provider: provider,
                modelIdentifier: model
            )
        }

        let updatedFingerprints = Dictionary(uniqueKeysWithValues: updatedCues.map {
            ($0.id, fingerprint(for: $0))
        })
        activeFingerprintByCueID = updatedFingerprints

        var preserved: [Int: DubbingRenderedCue] = [:]
        var aliases: [(cueID: Int, sourceURL: URL, fingerprint: String)] = []
        for remap in plan.unaffectedCues {
            let previousFingerprint = fingerprint(for: remap.previous)
            guard let rendered = previousRendered[remap.previous.id],
                  rendered.fingerprint == previousFingerprint,
                  let updatedFingerprint = updatedFingerprints[remap.updated.id] else { continue }
            preserved[remap.updated.id] = DubbingRenderedCue(
                id: remap.updated.id,
                startSeconds: remap.updated.startSeconds,
                endSeconds: remap.updated.endSeconds,
                audioDuration: rendered.audioDuration,
                audioURL: rendered.audioURL,
                fingerprint: updatedFingerprint
            )
            if let savedRate = playbackRateByFingerprint[previousFingerprint] {
                playbackRateByFingerprint[updatedFingerprint] = savedRate
            }
            if previousFingerprint != updatedFingerprint {
                aliases.append((remap.updated.id, rendered.audioURL, updatedFingerprint))
            }
        }
        renderedByCueID = preserved
        persistPlaybackRates()

        let sourceRendered = plan.sourceCues.compactMap { cue -> DubbingRenderedCue? in
            let expectedFingerprint = fingerprint(for: cue)
            guard let rendered = previousRendered[cue.id],
                  rendered.fingerprint == expectedFingerprint else { return nil }
            return rendered.applyingPlaybackRate(playbackRateByFingerprint[expectedFingerprint])
        }
        let canMergeAudio = sourceRendered.count == plan.sourceCues.count
        let mergedFingerprint = fingerprint(for: plan.mergedCue)
        let cache = self.cache
        let generation = UUID()
        mergeAudioGeneration = generation

        if canMergeAudio {
            renderingCueIDs.insert(plan.mergedCue.id)
            statusMessage = L10n.format("Đang gộp âm thanh của %d cue…", sourceRendered.count)
            errorMessage = nil
        }

        mergeAudioTask = Task { [weak self] in
            guard let self else { return }
            do {
                for alias in aliases {
                    try Task.checkCancellation()
                    let aliasURL = try await Task.detached(priority: .utility) {
                        try cache.aliasClip(from: alias.sourceURL, for: alias.fingerprint)
                    }.value
                    if self.mergeAudioGeneration == generation,
                       let current = self.renderedByCueID[alias.cueID],
                       current.fingerprint == alias.fingerprint {
                        self.renderedByCueID[alias.cueID] = DubbingRenderedCue(
                            id: current.id,
                            startSeconds: current.startSeconds,
                            endSeconds: current.endSeconds,
                            audioDuration: current.audioDuration,
                            audioURL: aliasURL,
                            fingerprint: current.fingerprint
                        )
                    }
                }

                guard canMergeAudio else {
                    if self.mergeAudioGeneration == generation {
                        self.mergeAudioTask = nil
                        self.mergeAudioGeneration = nil
                    }
                    self.refreshCacheUsage()
                    return
                }
                let finalURL: URL
                if let existing = cache.existingClipURL(for: mergedFingerprint) {
                    finalURL = existing
                } else {
                    let temporaryURL = try cache.temporaryMergedClipURL()
                    do {
                        let clips = sourceRendered.map { rendered in
                            DubbingAudioMergeClip(
                                audioURL: rendered.audioURL,
                                startOffset: rendered.startSeconds - plan.mergedCue.startSeconds,
                                playbackRate: rendered.playbackRate
                            )
                        }
                        _ = try await DubbingAudioMergeService.merge(
                            clips: clips,
                            outputURL: temporaryURL
                        )
                        try Task.checkCancellation()
                        finalURL = try cache.commitMergedClip(
                            from: temporaryURL,
                            for: mergedFingerprint
                        )
                    } catch {
                        try? FileManager.default.removeItem(at: temporaryURL)
                        throw error
                    }
                }

                let duration = await DubbingCacheStore.audioDuration(at: finalURL)
                guard DubbingAudioValidation.isPlausible(
                    duration: duration,
                    text: plan.mergedCue.text
                ) else {
                    cache.removeClip(for: mergedFingerprint)
                    throw DubbingError.invalidAudioBuffer
                }
                guard !Task.isCancelled,
                      self.mergeAudioGeneration == generation,
                      self.activeFingerprintByCueID[plan.mergedCue.id] == mergedFingerprint else {
                    if self.mergeAudioGeneration == generation {
                        self.renderingCueIDs.remove(plan.mergedCue.id)
                        self.mergeAudioTask = nil
                        self.mergeAudioGeneration = nil
                    }
                    return
                }
                self.cacheLoadTask?.cancel()
                self.renderedByCueID[plan.mergedCue.id] = DubbingRenderedCue(
                    id: plan.mergedCue.id,
                    startSeconds: plan.mergedCue.startSeconds,
                    endSeconds: plan.mergedCue.endSeconds,
                    audioDuration: duration,
                    audioURL: finalURL,
                    fingerprint: mergedFingerprint
                )
                self.renderingCueIDs.remove(plan.mergedCue.id)
                self.mergeAudioTask = nil
                self.mergeAudioGeneration = nil
                self.statusMessage = L10n.format("Đã gộp âm thanh của %d cue.", sourceRendered.count)
                self.refreshCacheUsage()
            } catch is CancellationError {
                if self.mergeAudioGeneration == generation {
                    self.renderingCueIDs.remove(plan.mergedCue.id)
                    self.mergeAudioTask = nil
                    self.mergeAudioGeneration = nil
                }
            } catch {
                let isCurrentGeneration = self.mergeAudioGeneration == generation
                if isCurrentGeneration {
                    self.renderingCueIDs.remove(plan.mergedCue.id)
                    self.mergeAudioTask = nil
                    self.mergeAudioGeneration = nil
                }
                if canMergeAudio,
                   isCurrentGeneration,
                   self.activeFingerprintByCueID[plan.mergedCue.id] == mergedFingerprint {
                    self.statusMessage = ""
                    self.errorMessage = L10n.format(
                        "Không thể gộp âm thanh lồng tiếng: %@",
                        error.localizedDescription
                    )
                }
                self.refreshCacheUsage()
            }
        }
    }

    func renderSelected(cues: [SRTSegment], selectedIDs: Set<Int>) {
        let selected = cues.filter { selectedIDs.contains($0.id) }
        startRendering(selected.isEmpty ? Array(cues.prefix(1)) : selected, allCues: cues)
    }

    func renderAll(cues: [SRTSegment]) {
        startRendering(cues, allCues: cues)
    }

    var effectiveRenderedCues: [DubbingRenderedCue] {
        renderedByCueID.values
            .map(applyingSavedPlaybackRate)
            .sorted { $0.startSeconds < $1.startSeconds }
    }

    func effectiveRenderedCue(cueID: Int) -> DubbingRenderedCue? {
        renderedByCueID[cueID].map(applyingSavedPlaybackRate)
    }

    func previewPlaybackRates(_ ratesByCueID: [Int: Double]) {
        guard !ratesByCueID.isEmpty else { return }
        var updated = playbackRateByFingerprint
        for (cueID, rate) in ratesByCueID {
            guard let cue = renderedByCueID[cueID] else { continue }
            updated[cue.fingerprint] = min(
                DubbingRenderedCue.maximumPlaybackRate,
                max(DubbingRenderedCue.minimumPlaybackRate, rate)
            )
        }
        playbackRateByFingerprint = updated
    }

    func commitPlaybackRateChanges(cueIDs: Set<Int>) {
        let count = cueIDs.filter { renderedByCueID[$0] != nil }.count
        guard count > 0 else { return }
        persistPlaybackRates()
        statusMessage = L10n.format("Đã kéo tốc độ cho %d cue.", count)
        let preview = AVPreviewService.shared
        synchronizePreviewPlayback(at: preview.currentTime, isPlaying: preview.isPlaying)
    }

    func resetPlaybackRate(cueIDs: Set<Int>) {
        let selected = cueIDs.compactMap { renderedByCueID[$0] }
        guard !selected.isEmpty else { return }
        for cue in selected { playbackRateByFingerprint.removeValue(forKey: cue.fingerprint) }
        persistPlaybackRates()
        statusMessage = L10n.format("Đã đưa %d cue về tốc độ tự nhiên.", selected.count)
        let preview = AVPreviewService.shared
        synchronizePreviewPlayback(at: preview.currentTime, isPlaying: preview.isPlaying)
    }

    func removeRenderedCues(cueIDs: Set<Int>) {
        let selected = cueIDs.compactMap { renderedByCueID[$0] }
        guard !selected.isEmpty else { return }
        playback.stopAll(restoreOriginalVolume: originalVolume)
        for cue in selected {
            try? cache.blockReuse(for: cue.fingerprint)
            cache.removeClip(for: cue.fingerprint)
            playbackRateByFingerprint.removeValue(forKey: cue.fingerprint)
            renderedByCueID.removeValue(forKey: cue.id)
        }
        persistPlaybackRates()
        statusMessage = L10n.format("Đã xóa giọng của %d cue.", selected.count)
        refreshCacheUsage()
    }

    func cancelRendering() {
        renderTask?.cancel()
        renderGeneration = nil
        renderTask = nil
        mergeAudioTask?.cancel()
        mergeAudioTask = nil
        mergeAudioGeneration = nil
        appleSpeech.stop()
        googleSpeech.stop()
        elevenSpeech.stop()
        maziaoSpeech.stop()
        renderingCueIDs.removeAll()
        statusMessage = L10n.string("Đã dừng tạo giọng.")
    }

    func preview(cueID: Int) {
        guard let rendered = effectiveRenderedCue(cueID: cueID) else { return }
        playback.audition(rendered)
    }

    /// Keeps the DUB lane audible with the main video preview. Skim remains
    /// silent; only committed playback drives synthesized speech.
    func synchronizePreviewPlayback(at seconds: Double, isPlaying: Bool) {
        playback.synchronize(
            cues: effectiveRenderedCues,
            mediaTime: seconds,
            isPlaying: isPlaying,
            originalVolume: originalVolume,
            dubVolume: dubVolume,
            duckOriginal: duckOriginal
        )
    }

    func exportMix(mediaURL: URL?, outputURL: URL) {
        guard let mediaURL else {
            errorMessage = L10n.string("Chưa có media để xuất bản lồng tiếng.")
            return
        }
        let clips = effectiveRenderedCues
        guard !clips.isEmpty else {
            errorMessage = L10n.string("Chưa có đoạn lồng tiếng nào để xuất.")
            return
        }
        isExporting = true
        statusMessage = L10n.string("Đang xuất bản lồng tiếng…")
        let settings = DubbingMixSettings(
            originalVolume: originalVolume,
            dubVolume: dubVolume,
            duckOriginal: duckOriginal,
            duckedOriginalVolume: min(originalVolume, 0.18),
            fadeDuration: 0.14
        )
        Task { [weak self] in
            do {
                try await DubbingMixExportService.export(
                    mediaURL: mediaURL,
                    renderedCues: clips,
                    settings: settings,
                    outputURL: outputURL
                )
                guard let self else { return }
                self.isExporting = false
                self.statusMessage = L10n.format("Đã xuất %@", outputURL.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                guard let self else { return }
                self.isExporting = false
                self.errorMessage = error.localizedDescription
                self.statusMessage = ""
            }
        }
    }

    func clearCache() {
        cancelRendering()
        playback.stopAll(restoreOriginalVolume: originalVolume)
        do {
            try cache.removeAll()
            renderedByCueID.removeAll()
            playbackRateByFingerprint.removeAll()
            defaults.removeObject(forKey: Keys.playbackRates)
            cacheUsage = .empty
            refreshCacheUsage()
            statusMessage = L10n.string("Đã xóa cache lồng tiếng.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyingSavedPlaybackRate(_ cue: DubbingRenderedCue) -> DubbingRenderedCue {
        cue.applyingPlaybackRate(playbackRateByFingerprint[cue.fingerprint])
    }

    var cacheSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: cacheUsage.allocatedBytes, countStyle: .file)
    }

    func refreshCacheUsage() {
        let generation = UUID()
        cacheUsageGeneration = generation
        let cache = self.cache
        Task { [weak self] in
            let usage = await Task.detached(priority: .utility) {
                (try? cache.usage()) ?? .empty
            }.value
            guard let self, self.cacheUsageGeneration == generation else { return }
            self.cacheUsage = usage
            self.cacheUsageGeneration = nil
        }
    }

    private func persistPlaybackRates() {
        defaults.set(playbackRateByFingerprint, forKey: Keys.playbackRates)
    }

    private func cachedClip(cue: SRTSegment, language: String, voice: String?, rate: Float,
                            provider: DubbingSpeechProvider, model: String) -> URL? {
        let fingerprint = DubbingFingerprint.make(cue: cue, localeIdentifier: language,
            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
        if let existing = cache.existingClipURL(for: fingerprint) { return existing }
        guard cache.allowsReuse(for: fingerprint) else { return nil }
        let previous = DubbingFingerprint.previousContent(cue: cue, localeIdentifier: language,
            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
        let legacy = provider == .elevenLabs && abs(rate - 0.5) >= 0.0001 ? "" :
            DubbingFingerprint.legacyTimingBound(cue: cue, localeIdentifier: language,
                voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
        if let migrated = (try? cache.migrateClip(from: previous, to: fingerprint))
            ?? (try? cache.migrateClip(from: legacy, to: fingerprint)) {
            if playbackRateByFingerprint[fingerprint] == nil,
               let saved = playbackRateByFingerprint[previous] ?? playbackRateByFingerprint[legacy] {
                playbackRateByFingerprint[fingerprint] = saved
                persistPlaybackRates()
            }
            return migrated
        }
        let content = DubbingFingerprint.speechContent(cue: cue, localeIdentifier: language,
            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
        return try? cache.reuseSpeech(content: content, fingerprint: fingerprint)
    }

    private func startRendering(_ cues: [SRTSegment], allCues: [SRTSegment]) {
        guard !cues.isEmpty, !isRendering else { return }
        renderTask?.cancel()
        cacheLoadTask?.cancel()
        let generation = UUID()
        renderGeneration = generation
        progressCurrent = 0
        progressTotal = cues.count
        statusMessage = L10n.format("Đang tạo giọng %@…", speechProvider.label)
        errorMessage = nil
        renderingCueIDs = Set(cues.map(\.id))

        let language = languageIdentifier
        let provider = speechProvider
        let model = selectedModelIdentifier
        let voice = selectedVoiceIdentifier
        let rate = speechRate
        let providerService = selectedSpeechService
        renderTask = Task { [weak self] in
            guard let self else { return }
            do {
                try self.cache.prepare()
                // Resolve migration/reuse before forming paid requests.
                for cue in cues {
                    _ = self.cachedClip(cue: cue, language: language, voice: voice, rate: rate,
                                        provider: provider, model: model)
                }
                let batchService = providerService as? DubbingSpeechBatchSynthesizing
                var batchByCueID: [Int: [DubbingSpeechRequest]] = [:]
                var batchPositionByCueID: [Int: (current: Int, total: Int)] = [:]
                if let batchService {
                    self.statusMessage = L10n.format("Đang chuẩn bị %d câu chưa có giọng…", cues.count)
                    let pending = cues.compactMap { cue -> DubbingSpeechRequest? in
                        let fingerprint = DubbingFingerprint.make(cue: cue, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                        guard self.cache.existingClipURL(for: fingerprint) == nil else { return nil }
                        return DubbingSpeechRequest(cueID: cue.id,
                            text: cue.text.replacingOccurrences(of: "\n", with: " "),
                            localeIdentifier: language, voiceIdentifier: voice, rate: rate,
                            outputURL: self.cache.clipURL(for: fingerprint), provider: provider, modelIdentifier: model)
                    }
                    let batches = try await batchService.renderBatches(for: pending)
                    for (batchOffset, batch) in batches.enumerated() {
                        for request in batch { batchByCueID[request.cueID] = batch }
                        for request in batch {
                            batchPositionByCueID[request.cueID] = (batchOffset + 1, batches.count)
                        }
                    }
                }
                if provider == .googleCloud || provider == .elevenLabs {
                    let pending = cues.filter { self.cachedClip(cue: $0, language: language, voice: voice,
                        rate: rate, provider: provider, model: model) == nil }
                    let groups = Dictionary(grouping: pending) {
                        DubbingFingerprint.speechContent(cue: $0, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                    }
                    // Generate repeated speech once; retain separate cue/composite identities.
                    var seenContent = Set<String>()
                    let unique = pending.filter {
                        seenContent.insert(DubbingFingerprint.speechContent(cue: $0, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)).inserted
                    }
                    var completedCount = cues.count - pending.count
                    self.progressCurrent = completedCount
                    try await DubbingRenderQueue.run(count: unique.count, operation: { index in
                        let cue = unique[index]
                        let fingerprint = DubbingFingerprint.make(cue: cue, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                        try await providerService.render(.init(cueID: cue.id, text: DubbingFingerprint.spokenText(cue.text),
                            localeIdentifier: language, voiceIdentifier: voice, rate: rate,
                            outputURL: self.cache.clipURL(for: fingerprint), provider: provider, modelIdentifier: model))
                        try Task.checkCancellation()
                        guard let url = self.cache.existingClipURL(for: fingerprint) else {
                            throw DubbingError.invalidAudioBuffer
                        }
                        let duration = await DubbingCacheStore.audioDuration(at: url)
                        guard DubbingAudioValidation.isPlausible(duration: duration, text: cue.text) else {
                            self.cache.removeClip(for: fingerprint)
                            throw DubbingError.invalidAudioBuffer
                        }
                        let content = DubbingFingerprint.speechContent(cue: cue, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                        try self.cache.registerSpeechReuse(content: content, fingerprint: fingerprint)
                        guard self.renderGeneration == generation else { throw CancellationError() }
                        for target in groups[content] ?? [cue] {
                            let targetID = DubbingFingerprint.make(cue: target, localeIdentifier: language,
                                voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                            let alias = try self.cache.aliasClip(from: url, for: targetID)
                            try self.cache.registerSpeechReuse(content: content, fingerprint: targetID)
                            if self.activeFingerprintByCueID[target.id] == targetID {
                                self.renderedByCueID[target.id] = .init(id: target.id, startSeconds: target.startSeconds,
                                    endSeconds: target.endSeconds, audioDuration: duration, audioURL: alias, fingerprint: targetID)
                            }
                        }
                    }, completed: { index in
                        guard self.renderGeneration == generation else { return }
                        let content = DubbingFingerprint.speechContent(cue: unique[index], localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model)
                        completedCount += groups[content]?.count ?? 1
                        self.progressCurrent = completedCount
                        self.statusMessage = L10n.format("Đang tạo câu %d/%d bằng %@…",
                                                        completedCount, cues.count, provider.label)
                    })
                }
                var processedCount = 0
                for cue in cues {
                    try Task.checkCancellation()
                    guard self.renderGeneration == generation else { throw CancellationError() }
                    let fingerprint = DubbingFingerprint.make(
                        cue: cue,
                        localeIdentifier: language,
                        voiceIdentifier: voice,
                        rate: rate,
                        provider: provider,
                        modelIdentifier: model
                    )
                    let outputURL = self.cache.clipURL(for: fingerprint)
                    if self.cachedClip(cue: cue, language: language, voice: voice, rate: rate,
                                       provider: provider, model: model) == nil {
                        if let batchService, let batch = batchByCueID[cue.id] {
                            let batchPosition = batchPositionByCueID[cue.id] ?? (1, 1)
                            try await batchService.renderBatch(batch) { [weak self] progress in
                                await self?.updateRenderProgress(
                                    progress,
                                    batchCurrent: batchPosition.current,
                                    batchTotal: batchPosition.total,
                                    generation: generation
                                )
                            }
                        } else {
                            self.statusMessage = L10n.format(
                                "Đang tạo câu %d/%d bằng %@…",
                                self.progressCurrent + 1,
                                self.progressTotal,
                                provider.label
                            )
                            try await providerService.render(
                                DubbingSpeechRequest(
                                    cueID: cue.id,
                                    text: DubbingFingerprint.spokenText(cue.text),
                                    localeIdentifier: language,
                                    voiceIdentifier: voice,
                                    rate: rate,
                                    outputURL: outputURL,
                                    provider: provider,
                                    modelIdentifier: model
                                )
                            )
                        }
                    }
                    let resolvedOutputURL = self.cache.existingClipURL(for: fingerprint) ?? outputURL
                    let duration = await DubbingCacheStore.audioDuration(at: resolvedOutputURL)
                    guard DubbingAudioValidation.isPlausible(duration: duration, text: cue.text) else {
                        self.cache.removeClip(for: fingerprint)
                        throw DubbingError.invalidAudioBuffer
                    }
                    try Task.checkCancellation()
                    guard self.renderGeneration == generation else { throw CancellationError() }
                    try self.cache.registerSpeechReuse(
                        content: DubbingFingerprint.speechContent(cue: cue, localeIdentifier: language,
                            voiceIdentifier: voice, rate: rate, provider: provider, modelIdentifier: model),
                        fingerprint: fingerprint)
                    guard self.activeFingerprintByCueID[cue.id] == nil
                            || self.activeFingerprintByCueID[cue.id] == fingerprint else { throw CancellationError() }
                    self.renderedByCueID[cue.id] = DubbingRenderedCue(
                        id: cue.id,
                        startSeconds: cue.startSeconds,
                        endSeconds: cue.endSeconds,
                        audioDuration: duration,
                        audioURL: resolvedOutputURL,
                        fingerprint: fingerprint
                    )
                    self.renderingCueIDs.remove(cue.id)
                    processedCount += 1
                    self.progressCurrent = max(self.progressCurrent, processedCount)
                }
                self.renderTask = nil
                self.renderingCueIDs.removeAll()
                self.statusMessage = L10n.format("Đã tạo giọng cho %d cue.", cues.count)
                self.refreshCacheUsage()
                self.synchronize(cues: allCues)
                if provider == .elevenLabs {
                    _ = try? await ElevenLabsQuotaService.refresh()
                } else if provider == .maziao {
                    _ = try? await MaziaoAPIClient.account()
                }
            } catch is CancellationError {
                guard self.renderGeneration == generation else { return }
                self.renderTask = nil
                self.renderingCueIDs.removeAll()
                self.statusMessage = L10n.string("Đã dừng tạo giọng.")
            } catch {
                guard self.renderGeneration == generation else { return }
                self.renderTask = nil
                self.renderingCueIDs.removeAll()
                if let dubbingError = error as? DubbingError,
                   case .missingCredential = dubbingError {
                    self.setCredentialAvailability(false, for: provider)
                }
                self.errorMessage = error.localizedDescription
                self.statusMessage = ""
            }
        }
    }

    private func updateRenderProgress(
        _ progress: DubbingRenderProgress,
        batchCurrent: Int,
        batchTotal: Int,
        generation: UUID
    ) {
        guard renderGeneration == generation, !Task.isCancelled else { return }
        switch progress {
        case .resuming:
            statusMessage = L10n.format("Nhóm %d/%d · Đang tiếp tục tác vụ Maziao đã gửi…", batchCurrent, batchTotal)
        case let .submitting(total):
            statusMessage = L10n.format(
                "Nhóm %d/%d · Đang gửi %d câu tới Maziao…",
                batchCurrent,
                batchTotal,
                total
            )
        case let .waiting(stage, elapsedSeconds, timeoutSeconds):
            let stageLabel: String
            switch stage {
            case .queued: stageLabel = L10n.string("đang xếp hàng")
            case .processing: stageLabel = L10n.string("đang xử lý")
            case .saving: stageLabel = L10n.string("đang lưu kết quả")
            }
            statusMessage = L10n.format(
                "Nhóm %d/%d · Maziao %@ · đã chờ %@ / tối đa %@",
                batchCurrent,
                batchTotal,
                stageLabel,
                formattedRenderDuration(elapsedSeconds),
                formattedRenderDuration(timeoutSeconds)
            )
        case let .downloading(current, total):
            statusMessage = L10n.format(
                "Nhóm %d/%d · Đang tải tệp %d/%d…",
                batchCurrent,
                batchTotal,
                current,
                total
            )
        case let .transcoding(current, total):
            statusMessage = L10n.format(
                "Nhóm %d/%d · Đang chuyển mã %d/%d…",
                batchCurrent,
                batchTotal,
                current,
                total
            )
        case let .committing(total):
            statusMessage = L10n.format(
                "Nhóm %d/%d · Đang lưu %d câu…",
                batchCurrent,
                batchTotal,
                total
            )
        }
    }

    private func formattedRenderDuration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }

    private func selectCompatibleVoiceIfNeeded() {
        let choices = voicesForSelectedLanguage
        guard !choices.isEmpty else {
            voiceIdentifier = ""
            return
        }
        if !choices.contains(where: { $0.id == voiceIdentifier }) {
            voiceIdentifier = choices.first?.id ?? ""
        }
    }

    private func selectCompatibleGoogleVoiceIfNeeded() {
        let choices = googleVoicesForSelectedModel
        guard !choices.isEmpty else {
            googleVoiceIdentifier = ""
            return
        }
        if !choices.contains(where: { $0.id == googleVoiceIdentifier }) {
            googleVoiceIdentifier = choices.first?.id ?? ""
        }
        if let selected = choices.first(where: { $0.id == googleVoiceIdentifier }) {
            adoptLanguage(from: selected.language)
        }
    }

    var selectedModelIdentifier: String {
        switch speechProvider {
        case .googleCloud: googleModel.rawValue
        case .maziao: maziaoModel.rawValue
        case .elevenLabs: elevenModel.rawValue
        case .appleOffline: "apple-system"
        }
    }

    var selectedModelLabel: String {
        switch speechProvider {
        case .googleCloud: googleModel.label
        case .maziao: maziaoModel.label
        case .elevenLabs: elevenModel.label
        case .appleOffline: "Apple System Voice"
        }
    }

    var selectedVoiceIdentifier: String? {
        switch speechProvider {
        case .googleCloud: googleVoiceIdentifier.isEmpty ? nil : googleVoiceIdentifier
        case .maziao: maziaoVoiceIdentifier.isEmpty ? nil : maziaoVoiceIdentifier
        case .elevenLabs: elevenVoiceIdentifier.isEmpty ? nil : elevenVoiceIdentifier
        case .appleOffline: voiceIdentifier.isEmpty ? nil : voiceIdentifier
        }
    }

    var selectedVoiceLabel: String {
        guard let identifier = selectedVoiceIdentifier else {
            return L10n.string("Chưa chọn giọng")
        }
        switch speechProvider {
        case .googleCloud:
            return googleVoicesForSelectedModel.first(where: { $0.id == identifier })?.name ?? identifier
        case .appleOffline:
            return voices.first(where: { $0.id == identifier })?.name ?? identifier
        case .maziao:
            return maziaoVoices.first(where: { $0.id == identifier })?.name ?? identifier
        case .elevenLabs:
            return elevenVoices.first(where: { $0.id == identifier })?.name ?? identifier
        }
    }

    func updateGoogleVoiceCatalog(_ voices: [DubbingCloudVoice]) {
        googleVoices = voices
        googleVoiceCatalogError = ""
        selectCompatibleGoogleVoiceIfNeeded()
    }

    func clearGoogleVoiceCatalog() {
        googleVoices = []
        googleVoiceCatalogError = ""
        selectCompatibleGoogleVoiceIfNeeded()
    }

    func refreshGoogleVoiceCatalog() async {
        guard hasGoogleCredential, !isRefreshingGoogleVoices else { return }
        isRefreshingGoogleVoices = true
        googleVoiceCatalogError = ""
        defer { isRefreshingGoogleVoices = false }
        do {
            updateGoogleVoiceCatalog(try await GoogleVoiceCatalogAPI.voices())
        } catch {
            if let dubbingError = error as? DubbingError,
               case .missingCredential = dubbingError {
                setCredentialAvailability(false, for: .googleCloud)
            }
            googleVoiceCatalogError = error.localizedDescription
        }
    }

    func updateMaziaoVoiceCatalog(_ voices: [MaziaoVoiceDescriptor]) {
        maziaoVoices = voices
        maziaoVoiceCatalogError = ""
        applyMaziaoSelection(MaziaoVoiceSelectionPolicy.reconcile(
            voices: voices,
            currentVoiceID: maziaoVoiceIdentifier,
            currentModel: maziaoModel
        ))
    }

    func clearMaziaoVoiceCatalog() {
        maziaoVoices = []
        maziaoVoiceCatalogError = ""
        maziaoVoiceIdentifier = ""
    }

    func refreshMaziaoVoiceCatalog() async {
        guard hasMaziaoCredential, !isRefreshingMaziaoVoices else { return }
        isRefreshingMaziaoVoices = true
        maziaoVoiceCatalogError = ""
        defer { isRefreshingMaziaoVoices = false }
        do {
            updateMaziaoVoiceCatalog(try await MaziaoAPIClient.voices())
        } catch {
            if let dubbingError = error as? DubbingError,
               case .missingCredential = dubbingError {
                setCredentialAvailability(false, for: .maziao)
            }
            maziaoVoiceCatalogError = error.localizedDescription
        }
    }

    func selectMaziaoModel(_ model: MaziaoDubbingModel) {
        applyMaziaoSelection(MaziaoVoiceSelectionPolicy.selectingModel(
            model,
            voices: maziaoVoices,
            currentVoiceID: maziaoVoiceIdentifier
        ))
    }

    func selectMaziaoVoice(_ voiceID: String) {
        applyMaziaoSelection(MaziaoVoiceSelectionPolicy.selectingVoice(
            voiceID,
            voices: maziaoVoices,
            currentModel: maziaoModel
        ))
    }

    func selectGoogleVoice(_ voiceID: String) {
        googleVoiceIdentifier = voiceID
        if let voice = googleVoicesForSelectedModel.first(where: { $0.id == voiceID }) {
            adoptLanguage(from: voice.language)
        }
    }

    func updateElevenVoiceCatalog(_ voices: [DubbingCloudVoice]) {
        elevenVoices = voices
        elevenVoiceCatalogError = ""
        if elevenVoiceIdentifier.isEmpty, let first = voices.first {
            selectElevenVoice(first.id)
        } else if let selected = voices.first(where: { $0.id == elevenVoiceIdentifier }) {
            adoptLanguage(from: selected.language)
        }
    }

    func clearElevenVoiceCatalog() {
        elevenVoices = []
        elevenVoiceCatalogError = ""
    }

    func refreshElevenVoiceCatalog() async {
        guard hasElevenLabsCredential, !isRefreshingElevenVoices else { return }
        isRefreshingElevenVoices = true
        elevenVoiceCatalogError = ""
        defer { isRefreshingElevenVoices = false }
        do {
            updateElevenVoiceCatalog(try await ElevenLabsVoiceCatalogAPI.voices())
        } catch {
            if let dubbingError = error as? DubbingError,
               case .missingCredential = dubbingError {
                setCredentialAvailability(false, for: .elevenLabs)
            }
            elevenVoiceCatalogError = error.localizedDescription
        }
    }

    func selectElevenVoice(_ voiceID: String) {
        elevenVoiceIdentifier = voiceID
        if let voice = elevenVoices.first(where: { $0.id == voiceID }) {
            adoptLanguage(from: voice.language)
        }
    }

    private func applyMaziaoSelection(_ selection: MaziaoVoiceSelection) {
        if maziaoModel != selection.model { maziaoModel = selection.model }
        if maziaoVoiceIdentifier != selection.voiceID { maziaoVoiceIdentifier = selection.voiceID }
        if let voice = maziaoVoices.first(where: { $0.id == selection.voiceID }) {
            adoptLanguage(from: voice.language)
        }
    }

    private func adoptLanguage(from identifier: String) {
        let canonical = DubbingVoiceCatalogPolicy.canonicalLocaleIdentifier(for: identifier)
        guard canonical != "und", languageIdentifier != canonical else { return }
        languageIdentifier = canonical
    }

    var selectedProviderReady: Bool {
        switch speechProvider {
        case .googleCloud: hasGoogleCredential && selectedVoiceIdentifier != nil
        case .maziao: hasMaziaoCredential && selectedVoiceIdentifier != nil
        case .elevenLabs: hasElevenLabsCredential && selectedVoiceIdentifier != nil
        case .appleOffline: selectedVoiceIdentifier != nil
        }
    }

    func hasCredential(for provider: DubbingSpeechProvider) -> Bool {
        switch provider {
        case .googleCloud: hasGoogleCredential
        case .maziao: hasMaziaoCredential
        case .elevenLabs: hasElevenLabsCredential
        case .appleOffline: true
        }
    }

    func setCredentialAvailability(_ available: Bool, for provider: DubbingSpeechProvider) {
        switch provider {
        case .googleCloud:
            hasGoogleCredential = available
            if !available { clearGoogleVoiceCatalog() }
        case .maziao:
            hasMaziaoCredential = available
            if !available { clearMaziaoVoiceCatalog() }
        case .elevenLabs:
            hasElevenLabsCredential = available
            if !available { clearElevenVoiceCatalog() }
        case .appleOffline: break
        }
    }

    private var selectedSpeechService: DubbingSpeechSynthesizing {
        switch speechProvider {
        case .googleCloud: googleSpeech
        case .maziao: maziaoSpeech
        case .elevenLabs: elevenSpeech
        case .appleOffline: appleSpeech
        }
    }
}
