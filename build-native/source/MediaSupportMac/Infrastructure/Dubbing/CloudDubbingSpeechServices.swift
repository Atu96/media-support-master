import AVFoundation
import Foundation

enum GoogleVoiceCatalogAPI {
    static func voices() async throws -> [DubbingCloudVoice] {
        let key = await DubbingCredentialAccess.shared.loadGoogle()
        guard !key.isEmpty else { throw DubbingError.missingCredential("Google Cloud TTS") }
        guard let endpoint = URL(string: "https://texttospeech.googleapis.com/v1/voices") else {
            throw DubbingError.providerResponse("Google voices endpoint không hợp lệ.")
        }
        var request = URLRequest(url: endpoint)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DubbingError.providerResponse(errorMessage(from: data, response: response))
        }
        return try GoogleVoiceCatalogDecoder.voices(from: data)
    }

    private static func errorMessage(from data: Data, response: URLResponse) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return (response as? HTTPURLResponse).map { "Google HTTP \($0.statusCode) [voices]" }
            ?? "Google không phản hồi khi tải giọng."
    }
}

enum ElevenLabsVoiceCatalogAPI {
    static func voices() async throws -> [DubbingCloudVoice] {
        let key = await DubbingCredentialAccess.shared.loadElevenLabs()
        guard !key.isEmpty else { throw DubbingError.missingCredential("ElevenLabs") }
        let maximumPages = 100
        var pageToken: String?
        var collected: [DubbingCloudVoice] = []
        var seenIDs: Set<String> = []

        for pageIndex in 0..<maximumPages {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            var queryItems = [
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "include_total_count", value: "true"),
                URLQueryItem(name: "sort", value: "name"),
                URLQueryItem(name: "sort_direction", value: "asc"),
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "next_page_token", value: pageToken)) }
            components.queryItems = queryItems
            var request = URLRequest(url: components.url!)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 45
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DubbingError.providerResponse(errorMessage(from: data, response: response))
            }
            let page = try ElevenLabsVoiceCatalogDecoder.page(from: data)
            for voice in page.voices where seenIDs.insert(voice.id).inserted {
                collected.append(voice)
            }
            guard page.hasMore else { return collected }
            guard let nextToken = page.nextPageToken, !nextToken.isEmpty, nextToken != pageToken else {
                throw DubbingError.providerResponse("ElevenLabs trả phân trang danh sách giọng không hợp lệ.")
            }
            if pageIndex == maximumPages - 1 {
                throw DubbingError.providerResponse("Danh sách giọng ElevenLabs vượt giới hạn đồng bộ an toàn.")
            }
            pageToken = nextToken
        }
        return collected
    }

    private static func errorMessage(from data: Data, response: URLResponse) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] {
            if let message = detail as? String { return message }
            if let detailObject = detail as? [String: Any], let message = detailObject["message"] as? String {
                return message
            }
        }
        return (response as? HTTPURLResponse).map { "ElevenLabs HTTP \($0.statusCode) [voices]" }
            ?? "ElevenLabs không phản hồi khi tải giọng."
    }
}

@MainActor
final class GoogleCloudDubbingService: DubbingSpeechSynthesizing {
    var availableVoices: [DubbingVoiceDescriptor] { [] }

    func render(_ request: DubbingSpeechRequest) async throws {
        let key = await DubbingCredentialAccess.shared.loadGoogle()
        guard !key.isEmpty else { throw DubbingError.missingCredential("Google Cloud TTS") }
        guard let voiceName = request.voiceIdentifier, !voiceName.isEmpty else {
            throw DubbingError.missingVoiceIdentifier("Google Cloud TTS")
        }
        guard let endpoint = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize") else {
            throw DubbingError.providerResponse("Google TTS endpoint không hợp lệ.")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60
        let speakingRate = min(2.0, max(0.5, Double(request.rate / 0.5)))
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": ["text": request.text],
            "voice": ["languageCode": request.localeIdentifier, "name": voiceName],
            "audioConfig": ["audioEncoding": "LINEAR16", "speakingRate": speakingRate],
        ])

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DubbingError.providerResponse(Self.errorMessage(from: data, fallback: response))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = object["audioContent"] as? String,
              let audioData = Data(base64Encoded: encoded), !audioData.isEmpty else {
            throw DubbingError.invalidAudioBuffer
        }
        ProviderUsageStore.recordGoogleCharacters(request.text)
        try await DubbingAudioTranscoder.writeCloudAudio(audioData, sourceExtension: "wav", to: request.outputURL)
    }

    func stop() {}

    private static func errorMessage(from data: Data, fallback response: URLResponse) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String { return message }
        return (response as? HTTPURLResponse).map { "Google HTTP \($0.statusCode)" } ?? "Google TTS không phản hồi."
    }
}

@MainActor
final class ElevenLabsDubbingService: DubbingSpeechSynthesizing {
    var availableVoices: [DubbingVoiceDescriptor] { [] }

    func render(_ request: DubbingSpeechRequest) async throws {
        let key = await DubbingCredentialAccess.shared.loadElevenLabs()
        guard !key.isEmpty else { throw DubbingError.missingCredential("ElevenLabs") }
        guard let voiceID = request.voiceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !voiceID.isEmpty else { throw DubbingError.missingVoiceIdentifier("ElevenLabs") }
        let encodedVoice = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? voiceID
        guard let endpoint = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoice)?output_format=mp3_44100_128") else {
            throw DubbingError.providerResponse("ElevenLabs endpoint không hợp lệ.")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 90
        urlRequest.httpBody = try ElevenLabsRequestEncoder.body(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DubbingError.providerResponse(Self.errorMessage(from: data, fallback: response))
        }
        guard !data.isEmpty else { throw DubbingError.invalidAudioBuffer }
        try await DubbingAudioTranscoder.writeCompressedMP3(data, to: request.outputURL)
    }

    func stop() {}

    private static func errorMessage(from data: Data, fallback response: URLResponse) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] {
            if let message = detail as? String { return message }
            if let detailObject = detail as? [String: Any], let message = detailObject["message"] as? String { return message }
        }
        return (response as? HTTPURLResponse).map { "ElevenLabs HTTP \($0.statusCode)" } ?? "ElevenLabs không phản hồi."
    }
}
