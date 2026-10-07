import Foundation

struct MaziaoAccountSnapshot: Codable, Equatable, Sendable {
    let remainingCredits: Int
    let updatedAt: Date
}

enum MaziaoAPIClient {
    private static let baseURL = URL(string: "https://app.maziao.com")!
    private static let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 75
        return URLSession(configuration: configuration)
    }()
    private static let audioSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    static func voices(language: String? = nil) async throws -> [MaziaoVoiceDescriptor] {
        let pageSize = 100
        let maximumPages = 200
        var offset = 0
        var collected: [MaziaoVoiceDescriptor] = []
        var seenIDs: Set<String> = []

        for pageIndex in 0..<maximumPages {
            try Task.checkCancellation()
            var components = URLComponents(url: baseURL.appendingPathComponent("api/voices"), resolvingAgainstBaseURL: false)!
            var items = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            if let language, !language.isEmpty {
                items.append(URLQueryItem(name: "language", value: language))
            }
            components.queryItems = items
            let data = try await send(method: "GET", url: components.url!, operation: .voices)
            let page = try MaziaoResponseDecoder.voicePage(from: data)
            for voice in page.voices where seenIDs.insert(voice.id).inserted {
                collected.append(voice)
            }

            let pageOffset = page.offset ?? offset
            let step = max(1, page.limit ?? page.voices.count)
            let nextOffset = pageOffset + step
            let hasMore = page.total.map { nextOffset < $0 } ?? (page.voices.count >= pageSize)
            guard hasMore else { return collected }
            guard !page.voices.isEmpty, nextOffset > offset else {
                throw DubbingError.providerResponse("Maziao trả phân trang danh sách giọng không hợp lệ.")
            }
            if pageIndex == maximumPages - 1 {
                throw DubbingError.providerResponse("Danh sách giọng Maziao vượt giới hạn đồng bộ an toàn.")
            }
            offset = nextOffset
        }
        return collected
    }

    static func voice(id: String) async throws -> MaziaoVoiceDescriptor {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await send(method: "GET", url: baseURL.appendingPathComponent("api/voices/\(encoded)"), operation: .voice)
        return try MaziaoResponseDecoder.voice(from: data)
    }

    static func account() async throws -> MaziaoAccountSnapshot {
        let data = try await send(method: "GET", url: baseURL.appendingPathComponent("api/auth/me"), operation: .account)
        let snapshot = MaziaoAccountSnapshot(
            remainingCredits: try MaziaoResponseDecoder.remainingCredits(from: data),
            updatedAt: Date()
        )
        ProviderUsageStore.saveMaziao(snapshot)
        return snapshot
    }

    static func previewAudio(from sourceURL: URL) async throws -> (data: Data, fileExtension: String) {
        let resolvedURL = sourceURL.scheme == nil
            ? URL(string: sourceURL.relativeString, relativeTo: baseURL)?.absoluteURL
            : sourceURL
        guard let resolvedURL,
              resolvedURL.scheme?.lowercased() == "https" else {
            throw DubbingError.providerResponse("URL nghe thử Maziao không hợp lệ.")
        }

        var request = URLRequest(url: resolvedURL)
        request.timeoutInterval = 30
        request.setValue("audio/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await audioSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else {
            throw DubbingError.providerResponse(errorMessage(from: data, response: response, operation: .previewAudio))
        }
        return (data, audioFileExtension(url: resolvedURL, mimeType: http.mimeType))
    }

    static func synthesize(
        _ request: DubbingSpeechRequest,
        progress: DubbingRenderProgressHandler? = nil
    ) async throws -> Data {
        guard let voiceID = request.voiceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !voiceID.isEmpty else {
            throw DubbingError.missingVoiceIdentifier("Maziao")
        }
        let speed = min(1.5, max(0.5, Double(request.rate / 0.5)))
        let body = try MaziaoRequestEncoder.submitBody(
            text: request.text,
            voiceID: voiceID,
            modelID: request.modelIdentifier,
            speed: speed
        )
        let urls = try await submitAndWait(
            body: body,
            expectedCount: 1,
            characterCount: request.text.count,
            progress: progress
        )
        await progress?(.downloading(current: 1, total: 1))
        return try await audio(from: urls[0])
    }

    static func batchAudioURLs(
        _ requests: [DubbingSpeechRequest],
        progress: DubbingRenderProgressHandler? = nil
    ) async throws -> [URL] {
        let body = try MaziaoRequestEncoder.batchBody(requests)
        return try await submitAndWait(
            body: body,
            expectedCount: requests.count,
            characterCount: requests.reduce(0) { $0 + $1.text.count },
            progress: progress
        )
    }

    static func audio(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        let (audio, response) = try await audioSession.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), !audio.isEmpty else {
            throw DubbingError.providerResponse(errorMessage(from: audio, response: response, operation: .resultAudio))
        }
        return audio
    }

    private static func submitAndWait(
        body: Data,
        expectedCount: Int,
        characterCount: Int,
        progress: DubbingRenderProgressHandler?
    ) async throws -> [URL] {
        try Task.checkCancellation()
        await progress?(.submitting(total: expectedCount))
        let submitData = try await send(
            method: "POST",
            url: baseURL.appendingPathComponent("api/tts/submit"),
            operation: .submit,
            body: body
        )
        let submit = try MaziaoResponseDecoder.submitReceipt(from: submitData)
        if let credits = submit.remainingCredits {
            ProviderUsageStore.saveMaziao(.init(remainingCredits: max(0, credits), updatedAt: Date()))
        }

        let timeout = MaziaoPollingPolicy.timeoutSeconds(
            characterCount: characterCount,
            partCount: expectedCount
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let deadline = clock.now.advanced(by: .seconds(timeout))
        var pollAttempt = 0
        var transientStatusFailures = 0
        while clock.now < deadline {
            try Task.checkCancellation()
            let statusBody = try JSONSerialization.data(withJSONObject: ["ids": [submit.taskID]])
            let statusData: Data
            do {
                statusData = try await send(
                    method: "POST",
                    url: baseURL.appendingPathComponent("api/tts/status"),
                    operation: .status,
                    body: statusBody
                )
                transientStatusFailures = 0
            } catch let error as URLError where isTransientStatusError(error) {
                transientStatusFailures += 1
                guard transientStatusFailures <= MaziaoPollingPolicy.maximumTransientStatusFailures else {
                    throw error
                }
                let delay = MaziaoPollingPolicy.pollIntervalSeconds(afterAttempt: pollAttempt)
                pollAttempt += 1
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            let statuses = try MaziaoResponseDecoder.taskStates(from: statusData)
            guard let status = statuses.first(where: { $0.id == submit.taskID }) else {
                throw DubbingError.providerResponse("Maziao không trả trạng thái tác vụ.")
            }
            switch status.status.lowercased() {
            case "completed", "success", "succeeded":
                return try MaziaoResponseDecoder.audioURLs(from: status, expectedCount: expectedCount)
            case "failed", "error", "cancelled", "canceled":
                throw DubbingError.providerResponse("Tác vụ Maziao không hoàn tất.")
            default:
                let stage: DubbingRemoteTaskStage
                switch status.status.lowercased() {
                case "processing", "running": stage = .processing
                case "saving", "exporting", "exportingsrt": stage = .saving
                default: stage = .queued
                }
                let elapsed = Int(startedAt.duration(to: clock.now).components.seconds)
                await progress?(.waiting(
                    stage: stage,
                    elapsedSeconds: max(0, elapsed),
                    timeoutSeconds: Int(timeout)
                ))
                let delay = MaziaoPollingPolicy.pollIntervalSeconds(afterAttempt: pollAttempt)
                pollAttempt += 1
                try await Task.sleep(for: .seconds(delay))
            }
        }
        let minutes = Int(ceil(timeout / 60))
        throw DubbingError.providerResponse(
            L10n.format(
                "Maziao vẫn đang xử lý sau %d phút. Tác vụ có thể tiếp tục trên Maziao; hãy kiểm tra tài khoản trước khi tạo lại để tránh trừ credit hai lần.",
                minutes
            )
        )
    }

    private static func send(method: String, url: URL, operation: MaziaoAPIOperation, body: Data? = nil) async throws -> Data {
        let key = await DubbingCredentialAccess.shared.loadMaziao()
        guard !key.isEmpty else { throw DubbingError.missingCredential("Maziao") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        switch operation {
        case .submit: request.timeoutInterval = 60
        case .status: request.timeoutInterval = 45
        default: request.timeoutInterval = 30
        }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await apiSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DubbingError.providerResponse(errorMessage(from: data, response: response, operation: operation).replacingOccurrences(of: key, with: "[redacted]"))
        }
        return data
    }

    private static func errorMessage(from data: Data, response: URLResponse, operation: MaziaoAPIOperation) -> String {
        MaziaoResponseDecoder.providerErrorMessage(
            from: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode,
            operation: operation
        )
    }

    private static func isTransientStatusError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private static func audioFileExtension(url: URL, mimeType: String?) -> String {
        switch mimeType?.lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/mp4", "audio/x-m4a": return "m4a"
        case "audio/aac": return "aac"
        case "audio/x-caf": return "caf"
        default:
            let pathExtension = url.pathExtension.lowercased()
            return pathExtension.isEmpty ? "mp3" : pathExtension
        }
    }
}

@MainActor
final class MaziaoDubbingSpeechService: DubbingSpeechBatchSynthesizing {
    var availableVoices: [DubbingVoiceDescriptor] { [] }

    func render(_ request: DubbingSpeechRequest) async throws {
        try await render(request, progress: nil)
    }

    private func render(
        _ request: DubbingSpeechRequest,
        progress: DubbingRenderProgressHandler?
    ) async throws {
        guard let voice = request.voiceIdentifier, !voice.isEmpty else {
            throw DubbingError.missingVoiceIdentifier("Maziao")
        }
        let audio = try await MaziaoAPIClient.synthesize(request, progress: progress)
        guard !audio.isEmpty else { throw DubbingError.invalidAudioBuffer }
        await progress?(.transcoding(current: 1, total: 1))
        try await DubbingAudioTranscoder.writeCloudAudio(audio, sourceExtension: "wav", to: request.outputURL)
        await progress?(.committing(total: 1))
    }

    func renderBatches(for requests: [DubbingSpeechRequest]) throws -> [[DubbingSpeechRequest]] {
        try MaziaoBatchPlanner.batches(for: requests)
    }

    func renderBatch(
        _ requests: [DubbingSpeechRequest],
        progress: DubbingRenderProgressHandler?
    ) async throws {
        guard !requests.isEmpty else { return }
        if requests.count == 1 { try await render(requests[0], progress: progress); return }
        let urls = try await MaziaoAPIClient.batchAudioURLs(requests, progress: progress)
        let staged = requests.map {
            $0.outputURL.deletingLastPathComponent().appendingPathComponent(".maziao-\(UUID().uuidString).caf")
        }
        defer { for url in staged { try? FileManager.default.removeItem(at: url) } }
        // Download/decode one result at a time; never keep a batch of PCM in memory.
        for index in requests.indices {
            try Task.checkCancellation()
            await progress?(.downloading(current: index + 1, total: requests.count))
            let audio = try await MaziaoAPIClient.audio(from: urls[index])
            await progress?(.transcoding(current: index + 1, total: requests.count))
            try await DubbingAudioTranscoder.writeCloudAudio(audio, sourceExtension: "wav", to: staged[index])
            let duration = await DubbingCacheStore.audioDuration(at: staged[index])
            guard DubbingAudioValidation.isPlausible(duration: duration, text: requests[index].text) else {
                throw DubbingError.invalidAudioBuffer
            }
        }
        var committed: [URL] = []
        do {
            await progress?(.committing(total: requests.count))
            for index in requests.indices {
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: staged[index], to: requests[index].outputURL)
                committed.append(requests[index].outputURL)
            }
        } catch {
            for url in committed { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    func stop() {}
}
