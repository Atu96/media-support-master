import Foundation
import CryptoKit

enum DubbingSpeechProvider: String, CaseIterable, Identifiable, Sendable {
    case googleCloud
    case maziao
    case elevenLabs
    case appleOffline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .googleCloud: "Google Cloud TTS"
        case .maziao: "Maziao"
        case .elevenLabs: "ElevenLabs"
        case .appleOffline: "Apple Offline"
        }
    }

    var detail: String {
        switch self {
        case .googleCloud: "Ưu tiên mặc định · dùng hạn mức miễn phí của tài khoản Google Cloud"
        case .maziao: "Giọng đa ngôn ngữ · có thư viện giọng và nghe mẫu sẵn"
        case .elevenLabs: "Giọng biểu cảm chất lượng cao · dùng Eleven v3"
        case .appleOffline: "Chỉ dùng giọng đã có trên máy Mac · không tự tải"
        }
    }

    var icon: String {
        switch self {
        case .googleCloud: "cloud.fill"
        case .maziao: "waveform.circle.fill"
        case .elevenLabs: "waveform.badge.sparkles"
        case .appleOffline: "desktopcomputer"
        }
    }
}

enum MaziaoDubbingModel: String, CaseIterable, Identifiable, Sendable {
    case lingualV2 = "lingual_speech_v2"
    case vieten = "vieten_speech"
    case jeck = "jeck_speech"
    case lingualBase = "lingual_speech_base"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .lingualV2: "Lingual Speech v2"
        case .vieten: "VietEN Speech"
        case .jeck: "Jeck Speech"
        case .lingualBase: "Lingual Speech Base"
        }
    }
}

struct MaziaoVoiceDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let gender: String
    let previewURL: URL?
    let modelID: String?
}

struct MaziaoVoicePage: Equatable, Sendable {
    let voices: [MaziaoVoiceDescriptor]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

struct DubbingVoiceCatalogItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let detail: String
}

struct DubbingVoiceCatalogGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let voices: [DubbingVoiceCatalogItem]
}

/// Pure grouping/search policy shared by Settings and the Dubbing inspector.
/// Country/language labels are rendered in the app's interface locale, while
/// matching is case/diacritic insensitive so `Viet Nam` also finds `Việt Nam`.
enum DubbingVoiceCatalogPolicy {
    static func localizedGender(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "female", "f", "nữ": L10n.string("Nữ")
        case "male", "m", "nam": L10n.string("Nam")
        case "neutral", "non-binary", "unisex": L10n.string("Trung tính")
        case "", "—": ""
        default: rawValue
        }
    }

    static func groups(
        voices: [DubbingVoiceCatalogItem],
        query: String,
        interfaceLocaleIdentifier: String
    ) -> [DubbingVoiceCatalogGroup] {
        let interfaceLocale = Locale(identifier: interfaceLocaleIdentifier)
        let grouped = Dictionary(grouping: voices) { canonicalLocaleIdentifier(for: $0.language) }
        let normalizedQuery = normalized(query, locale: interfaceLocale)

        return grouped.compactMap { identifier, groupVoices -> DubbingVoiceCatalogGroup? in
            let title = localizedGroupTitle(for: identifier, interfaceLocale: interfaceLocale)
            let groupMatches = normalizedQuery.isEmpty
                || normalized(title, locale: interfaceLocale).contains(normalizedQuery)
                || normalized(identifier, locale: interfaceLocale).contains(normalizedQuery)
            let matches = groupMatches ? groupVoices : groupVoices.filter { voice in
                normalized([voice.name, voice.detail, voice.language].joined(separator: " "), locale: interfaceLocale)
                    .contains(normalizedQuery)
            }
            guard !matches.isEmpty else { return nil }
            return DubbingVoiceCatalogGroup(
                id: identifier,
                title: title,
                voices: matches.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func canonicalLocaleIdentifier(for rawIdentifier: String) -> String {
        let sanitized = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !sanitized.isEmpty, sanitized != "—", sanitized.lowercased() != "und" else {
            return "und"
        }
        let locale = Locale(identifier: sanitized)
        guard let language = locale.language.languageCode?.identifier.lowercased(), !language.isEmpty else {
            return sanitized
        }
        if let region = locale.region?.identifier.uppercased(), !region.isEmpty {
            return "\(language)-\(region)"
        }
        let inferredRegions = [
            "vi": "VN", "en": "US", "ko": "KR", "ja": "JP", "zh": "CN",
            "fr": "FR", "de": "DE", "es": "ES", "pt": "BR", "it": "IT",
            "ru": "RU", "ar": "SA", "hi": "IN", "id": "ID", "th": "TH",
            "tr": "TR", "pl": "PL", "nl": "NL", "sv": "SE", "uk": "UA",
        ]
        return inferredRegions[language].map { "\(language)-\($0)" } ?? language
    }

    private static func localizedGroupTitle(for identifier: String, interfaceLocale: Locale) -> String {
        guard identifier != "und" else { return L10n.string("Khác") }
        let locale = Locale(identifier: identifier)
        let languageCode = locale.language.languageCode?.identifier ?? identifier
        let language = interfaceLocale.localizedString(forLanguageCode: languageCode) ?? languageCode
        guard let regionCode = locale.region?.identifier,
              let country = interfaceLocale.localizedString(forRegionCode: regionCode) else {
            return language.capitalized(with: interfaceLocale)
        }
        return "\(country) · \(language.capitalized(with: interfaceLocale))"
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MaziaoVoiceSelection: Equatable, Sendable {
    let voiceID: String
    let model: MaziaoDubbingModel
}

enum MaziaoVoiceSelectionPolicy {
    static func reconcile(
        voices: [MaziaoVoiceDescriptor],
        currentVoiceID: String,
        currentModel: MaziaoDubbingModel
    ) -> MaziaoVoiceSelection {
        let voice = voices.first(where: { $0.id == currentVoiceID })
            ?? voices.first(where: { $0.modelID == currentModel.rawValue })
            ?? voices.first
        let model = voice?.modelID.flatMap(MaziaoDubbingModel.init(rawValue:)) ?? currentModel
        return MaziaoVoiceSelection(voiceID: voice?.id ?? "", model: model)
    }

    static func selectingModel(
        _ model: MaziaoDubbingModel,
        voices: [MaziaoVoiceDescriptor],
        currentVoiceID: String
    ) -> MaziaoVoiceSelection {
        let current = voices.first(where: { $0.id == currentVoiceID })
        let voiceID: String
        if current?.modelID == nil || current?.modelID == model.rawValue {
            voiceID = current?.id ?? voices.first(where: { $0.modelID == model.rawValue })?.id ?? ""
        } else {
            voiceID = voices.first(where: { $0.modelID == model.rawValue })?.id ?? ""
        }
        return MaziaoVoiceSelection(voiceID: voiceID, model: model)
    }

    static func selectingVoice(
        _ voiceID: String,
        voices: [MaziaoVoiceDescriptor],
        currentModel: MaziaoDubbingModel
    ) -> MaziaoVoiceSelection {
        let model = voices.first(where: { $0.id == voiceID })?.modelID
            .flatMap(MaziaoDubbingModel.init(rawValue:)) ?? currentModel
        return MaziaoVoiceSelection(voiceID: voiceID, model: model)
    }
}

enum GoogleDubbingModel: String, CaseIterable, Identifiable, Sendable {
    case chirp3HD = "chirp-3-hd"
    case neural2 = "neural2"
    case wavenet = "wavenet"
    case standard = "standard"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chirp3HD: "Chirp 3 HD"
        case .neural2: "Neural2"
        case .wavenet: "WaveNet"
        case .standard: "Standard"
        }
    }

    var voices: [DubbingCloudVoice] {
        switch self {
        case .chirp3HD:
            [
                .init(id: "vi-VN-Chirp3-HD-Leda", name: "Leda", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Chirp3-HD-Sulafat", name: "Sulafat", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Chirp3-HD-Zephyr", name: "Zephyr", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Chirp3-HD-Orus", name: "Orus", gender: "Nam", language: "vi-VN"),
                .init(id: "vi-VN-Chirp3-HD-Puck", name: "Puck", gender: "Nam", language: "vi-VN"),
            ]
        case .neural2:
            [
                .init(id: "vi-VN-Neural2-A", name: "Neural2 A", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Neural2-D", name: "Neural2 D", gender: "Nam", language: "vi-VN"),
            ]
        case .wavenet:
            [
                .init(id: "vi-VN-Wavenet-A", name: "WaveNet A", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Wavenet-B", name: "WaveNet B", gender: "Nam", language: "vi-VN"),
                .init(id: "vi-VN-Wavenet-C", name: "WaveNet C", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Wavenet-D", name: "WaveNet D", gender: "Nam", language: "vi-VN"),
            ]
        case .standard:
            [
                .init(id: "vi-VN-Standard-A", name: "Standard A", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Standard-B", name: "Standard B", gender: "Nam", language: "vi-VN"),
                .init(id: "vi-VN-Standard-C", name: "Standard C", gender: "Nữ", language: "vi-VN"),
                .init(id: "vi-VN-Standard-D", name: "Standard D", gender: "Nam", language: "vi-VN"),
            ]
        }
    }

    func matches(voiceIdentifier: String) -> Bool {
        let name = voiceIdentifier.lowercased()
        return switch self {
        case .chirp3HD: name.contains("chirp3-hd")
        case .neural2: name.contains("neural2")
        case .wavenet: name.contains("wavenet")
        case .standard: name.contains("standard")
        }
    }
}

enum ElevenLabsDubbingModel: String, CaseIterable, Identifiable, Sendable {
    case v3 = "eleven_v3"
    case flashV25 = "eleven_flash_v2_5"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .v3: "Eleven v3"
        case .flashV25: "Flash v2.5"
        }
    }
}

struct DubbingCloudVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let gender: String
    let language: String
    let previewURL: URL?
    let modelIDs: Set<String>
    let category: String

    init(
        id: String,
        name: String,
        gender: String,
        language: String = "und",
        previewURL: URL? = nil,
        modelIDs: Set<String> = [],
        category: String = ""
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.language = language
        self.previewURL = previewURL
        self.modelIDs = modelIDs
        self.category = category
    }
}

struct ElevenLabsVoicePage: Equatable, Sendable {
    let voices: [DubbingCloudVoice]
    let hasMore: Bool
    let nextPageToken: String?
    let totalCount: Int?
}

enum GoogleVoiceCatalogDecoder {
    private struct Response: Decodable { let voices: [Voice] }
    private struct Voice: Decodable {
        let name: String
        let languageCodes: [String]
        let ssmlGender: String?
    }

    static func voices(from data: Data) throws -> [DubbingCloudVoice] {
        try JSONDecoder().decode(Response.self, from: data).voices.map { voice in
            DubbingCloudVoice(
                id: voice.name,
                name: voice.name.split(separator: "-").last.map(String.init) ?? voice.name,
                gender: voice.ssmlGender?.lowercased().capitalized ?? "—",
                language: voice.languageCodes.first ?? "und"
            )
        }
    }
}

enum ElevenLabsVoiceCatalogDecoder {
    private struct Response: Decodable {
        let voices: [Voice]
        let hasMore: Bool
        let nextPageToken: String?
        let totalCount: Int?

        enum CodingKeys: String, CodingKey {
            case voices
            case hasMore = "has_more"
            case nextPageToken = "next_page_token"
            case totalCount = "total_count"
        }
    }

    private struct Voice: Decodable {
        let voiceID: String
        let name: String?
        let category: String?
        let labels: [String: String]?
        let previewURL: URL?
        let verifiedLanguages: [VerifiedLanguage]?
        let highQualityBaseModelIDs: [String]?

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name, category, labels
            case previewURL = "preview_url"
            case verifiedLanguages = "verified_languages"
            case highQualityBaseModelIDs = "high_quality_base_model_ids"
        }
    }

    private struct VerifiedLanguage: Decodable {
        let language: String?
        let modelID: String?
        let locale: String?
        let previewURL: URL?

        enum CodingKeys: String, CodingKey {
            case language, locale
            case modelID = "model_id"
            case previewURL = "preview_url"
        }
    }

    static func page(from data: Data) throws -> ElevenLabsVoicePage {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return ElevenLabsVoicePage(
            voices: response.voices.map { voice in
                let verified = voice.verifiedLanguages?.first
                let language = verified?.locale ?? verified?.language ?? voice.labels?["language"] ?? "und"
                let modelIDs = Set((voice.verifiedLanguages ?? []).compactMap(\.modelID)
                    + (voice.highQualityBaseModelIDs ?? []))
                return DubbingCloudVoice(
                    id: voice.voiceID,
                    name: voice.name ?? voice.voiceID,
                    gender: voice.labels?["gender"] ?? "—",
                    language: language,
                    previewURL: voice.previewURL ?? verified?.previewURL,
                    modelIDs: modelIDs,
                    category: voice.category ?? ""
                )
            },
            hasMore: response.hasMore,
            nextPageToken: response.nextPageToken,
            totalCount: response.totalCount
        )
    }
}

struct DubbingVoiceDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let qualityLabel: String
}

struct DubbingSpeechRequest: Sendable {
    let cueID: Int
    let text: String
    let localeIdentifier: String
    let voiceIdentifier: String?
    let rate: Float
    let outputURL: URL
    var provider: DubbingSpeechProvider = .appleOffline
    var modelIdentifier: String = "apple-system"
}

@MainActor
protocol DubbingSpeechSynthesizing: AnyObject {
    var availableVoices: [DubbingVoiceDescriptor] { get }
    func render(_ request: DubbingSpeechRequest) async throws
    func stop()
}

enum DubbingToolbarAvailability {
    static func canRenderSelected(
        hasSubtitleSelection: Bool,
        providerReady: Bool,
        isRendering: Bool
    ) -> Bool {
        hasSubtitleSelection && providerReady && !isRendering
    }

    static func canRenderAll(
        hasCues: Bool,
        providerReady: Bool,
        isRendering: Bool
    ) -> Bool {
        hasCues && providerReady && !isRendering
    }
}

enum DubbingRemoteTaskStage: Sendable, Equatable {
    case queued
    case processing
    case saving
}

enum DubbingRenderProgress: Sendable, Equatable {
    case submitting(total: Int)
    case resuming
    case waiting(stage: DubbingRemoteTaskStage, elapsedSeconds: Int, timeoutSeconds: Int)
    case downloading(current: Int, total: Int)
    case transcoding(current: Int, total: Int)
    case committing(total: Int)
}

typealias DubbingRenderProgressHandler = @Sendable (DubbingRenderProgress) async -> Void

/// Optional provider capability; session still owns cue/cache/progress state.
@MainActor
protocol DubbingSpeechBatchSynthesizing: DubbingSpeechSynthesizing {
    func renderBatches(for requests: [DubbingSpeechRequest]) async throws -> [[DubbingSpeechRequest]]
    func renderBatch(
        _ requests: [DubbingSpeechRequest],
        progress: DubbingRenderProgressHandler?
    ) async throws
}

struct DubbingRenderedCue: Identifiable, Equatable, Sendable {
    enum Fit: String, Sendable {
        case fits
        case adjusted
        case needsReview
    }

    let id: Int
    let startSeconds: Double
    let endSeconds: Double
    let audioDuration: Double
    let audioURL: URL
    let fingerprint: String
    var playbackRateOverride: Double? = nil

    var cueDuration: Double { max(0, endSeconds - startSeconds) }

    static let minimumPlaybackRate = 0.25
    static let maximumPlaybackRate = 4.0

    /// Natural speech is the default. A rate only changes after an explicit
    /// user action, so a long title never stretches a short voice by itself.
    var playbackRate: Double {
        guard let playbackRateOverride, playbackRateOverride.isFinite else { return 1 }
        return min(Self.maximumPlaybackRate, max(Self.minimumPlaybackRate, playbackRateOverride))
    }

    var playedDuration: Double {
        guard audioDuration.isFinite, audioDuration > 0 else { return 0 }
        return audioDuration / playbackRate
    }

    var fit: Fit {
        guard playedDuration <= cueDuration + 0.08 else { return .needsReview }
        return abs(playbackRate - 1) <= 0.001 ? .fits : .adjusted
    }

    func updatingTiming(from cue: SRTSegment) -> DubbingRenderedCue {
        DubbingRenderedCue(
            id: id,
            startSeconds: cue.startSeconds,
            endSeconds: cue.endSeconds,
            audioDuration: audioDuration,
            audioURL: audioURL,
            fingerprint: fingerprint,
            playbackRateOverride: playbackRateOverride
        )
    }

    func applyingPlaybackRate(_ rate: Double?) -> DubbingRenderedCue {
        var copy = self
        copy.playbackRateOverride = rate
        return copy
    }
}

struct DubbingCueRemap: Sendable {
    let previous: SRTSegment
    let updated: SRTSegment
}

/// Describes the one structural edit whose audio can be preserved safely:
/// adjacent cues are replaced by one cue while every cue around them keeps
/// the same text and timing. IDs after the edit may be reindexed.
struct DubbingMergePreservationPlan: Sendable {
    let sourceCues: [SRTSegment]
    let mergedCue: SRTSegment
    let unaffectedCues: [DubbingCueRemap]

    static func make(
        previousCues: [SRTSegment],
        updatedCues: [SRTSegment],
        mergedSourceIDs: Set<Int>
    ) -> DubbingMergePreservationPlan? {
        guard mergedSourceIDs.count >= 2 else { return nil }
        let selectedIndices = previousCues.indices.filter {
            mergedSourceIDs.contains(previousCues[$0].id)
        }
        guard selectedIndices.count == mergedSourceIDs.count,
              let firstIndex = selectedIndices.first,
              let lastIndex = selectedIndices.last,
              selectedIndices == Array(firstIndex...lastIndex),
              updatedCues.count == previousCues.count - selectedIndices.count + 1,
              updatedCues.indices.contains(firstIndex) else {
            return nil
        }

        let sourceCues = Array(previousCues[firstIndex...lastIndex])
        let mergedCue = updatedCues[firstIndex]
        guard let firstSource = sourceCues.first,
              let lastSource = sourceCues.last,
              abs(mergedCue.startSeconds - firstSource.startSeconds) < 0.001,
              abs(mergedCue.endSeconds - lastSource.endSeconds) < 0.001 else {
            return nil
        }

        var unaffected: [DubbingCueRemap] = []
        unaffected.reserveCapacity(updatedCues.count - 1)
        for previousIndex in previousCues.indices where !selectedIndices.contains(previousIndex) {
            let updatedIndex = previousIndex < firstIndex
                ? previousIndex
                : previousIndex - selectedIndices.count + 1
            guard updatedCues.indices.contains(updatedIndex) else { return nil }
            let previous = previousCues[previousIndex]
            let updated = updatedCues[updatedIndex]
            guard previous.text == updated.text,
                  abs(previous.startSeconds - updated.startSeconds) < 0.001,
                  abs(previous.endSeconds - updated.endSeconds) < 0.001 else {
                return nil
            }
            unaffected.append(DubbingCueRemap(previous: previous, updated: updated))
        }
        return DubbingMergePreservationPlan(
            sourceCues: sourceCues,
            mergedCue: mergedCue,
            unaffectedCues: unaffected
        )
    }
}

enum DubbingAudioValidation {
    /// Rejects header-only / truncated TTS output while still allowing very short spoken cues.
    static func minimumPlausibleDuration(for text: String) -> Double {
        let spokenCharacters = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.alphanumerics.contains(scalar) { count += 1 }
        }
        return min(0.35, max(0.08, Double(spokenCharacters) * 0.012))
    }

    static func isPlausible(duration: Double, text: String) -> Bool {
        duration.isFinite && duration >= minimumPlausibleDuration(for: text)
    }
}

struct DubbingMixSettings: Sendable {
    var originalVolume: Float
    var dubVolume: Float
    var duckOriginal: Bool
    var duckedOriginalVolume: Float
    var fadeDuration: Double

    static let `default` = DubbingMixSettings(
        originalVolume: 1,
        dubVolume: 1,
        duckOriginal: true,
        duckedOriginalVolume: 0.18,
        fadeDuration: 0.14
    )
}

enum DubbingPlaybackMath {
    static func expectedAudioTime(for cue: DubbingRenderedCue, mediaTime: Double) -> Double {
        min(cue.audioDuration, max(0, mediaTime - cue.startSeconds) * cue.playbackRate)
    }

    static func shouldCorrectDrift(
        actualAudioTime: Double,
        expectedAudioTime: Double,
        secondsSinceLastSeek: Double
    ) -> Bool {
        let drift = actualAudioTime.isFinite
            ? abs(actualAudioTime - expectedAudioTime)
            : .infinity
        return drift > 0.12 && secondsSinceLastSeek > 0.35
    }
}

enum DubbingFingerprint {
    static let schema = "msm-dub-v3-spoken"
    private static let legacySchema = "msm-dub-v1"

    static func make(
        cue: SRTSegment,
        localeIdentifier: String,
        voiceIdentifier: String?,
        rate: Float,
        provider: DubbingSpeechProvider = .appleOffline,
        modelIdentifier: String = "apple-system"
    ) -> String {
        let payload = [
            schema,
            String(cue.id),
            localeIdentifier,
            voiceIdentifier ?? "system",
            String(format: "%.4f", rate),
            provider.rawValue,
            modelIdentifier,
            spokenText(cue.text),
        ].joined(separator: "\u{001F}")
        return fnv1a64(payload)
    }

    static func spokenText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Only independently generated speech may be indexed with this ID-free key.
    /// Composite audio stays cue-specific because gaps/overlaps are part of that audio.
    static func speechContent(cue: SRTSegment, localeIdentifier: String, voiceIdentifier: String?,
                              rate: Float, provider: DubbingSpeechProvider, modelIdentifier: String) -> String {
        let fields = [schema, localeIdentifier, voiceIdentifier ?? "system", String(format: "%.4f", rate),
                      provider.rawValue, modelIdentifier, spokenText(cue.text)]
        let data = (try? JSONEncoder().encode(fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func previousContent(cue: SRTSegment, localeIdentifier: String, voiceIdentifier: String?,
                                rate: Float, provider: DubbingSpeechProvider, modelIdentifier: String) -> String {
        // Old ElevenLabs ignored generation speed; only its natural-speed audio is compatible.
        guard provider != .elevenLabs || abs(rate - 0.5) < 0.0001 else { return "" }
        return fnv1a64(["msm-dub-v2-content", String(cue.id), localeIdentifier, voiceIdentifier ?? "system",
                       String(format: "%.4f", rate), provider.rawValue, modelIdentifier, cue.text]
            .joined(separator: "\u{001F}"))
    }

    /// Finds clips created before cue timing became independent from TTS cache identity.
    static func legacyTimingBound(
        cue: SRTSegment,
        localeIdentifier: String,
        voiceIdentifier: String?,
        rate: Float,
        provider: DubbingSpeechProvider = .appleOffline,
        modelIdentifier: String = "apple-system"
    ) -> String {
        let payload = [
            legacySchema,
            String(cue.id),
            String(format: "%.3f", cue.startSeconds),
            String(format: "%.3f", cue.endSeconds),
            localeIdentifier,
            voiceIdentifier ?? "system",
            String(format: "%.4f", rate),
            provider.rawValue,
            modelIdentifier,
            cue.text,
        ].joined(separator: "\u{001F}")
        return fnv1a64(payload)
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

enum DubbingError: LocalizedError {
    case emptyText
    case noVoice(String)
    case invalidAudioBuffer
    case speechTimedOut
    case missingMedia
    case missingRenderedClips
    case missingAudioTrack(URL)
    case cannotCreateComposition
    case exportFailed(String)
    case missingCredential(String)
    case missingVoiceIdentifier(String)
    case providerResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyText: "Cue không có nội dung để lồng tiếng."
        case let .noVoice(language): "Máy chưa có giọng đọc cho \(language)."
        case .invalidAudioBuffer: "Apple TTS không trả về dữ liệu âm thanh hợp lệ."
        case .speechTimedOut: "Apple TTS phản hồi quá lâu. Hãy thử lại hoặc chọn giọng khác."
        case .missingMedia: "Chưa có media để xuất bản lồng tiếng."
        case .missingRenderedClips: "Chưa có đoạn lồng tiếng nào để xuất."
        case let .missingAudioTrack(url): "Không đọc được audio lồng tiếng: \(url.lastPathComponent)"
        case .cannotCreateComposition: "Không thể tạo timeline âm thanh để xuất."
        case let .exportFailed(message): "Không thể xuất bản lồng tiếng: \(message)"
        case let .missingCredential(provider): "Chưa có API key cho \(provider). Hãy mở Cài đặt → Lồng tiếng."
        case let .missingVoiceIdentifier(provider): "Chưa chọn giọng cho \(provider). Hãy mở Cài đặt → Lồng tiếng."
        case let .providerResponse(message): "Dịch vụ giọng nói trả lỗi: \(message)"
        }
    }
}
