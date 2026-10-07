@preconcurrency import AVFoundation
import Foundation

enum GroqSpeechService {
    private static let endpoint = URL(
        string: "https://api.groq.com/openai/v1/audio/transcriptions"
    )!
    /// M4A 8 phút thường nằm an toàn dưới giới hạn upload 25 MB của free tier.
    private static let chunkDuration: Double = 8 * 60
    private static let safeUploadBytes: Int64 = 24 * 1_024 * 1_024

    static func transcribeToSRT(
        mediaURL: URL,
        outputURL: URL,
        sourceLanguage: String,
        model: GroqSpeechModel,
        wrapStyle: SubtitleWrapStyle,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        let key = GroqCredentialStore.load()
        guard !key.isEmpty else {
            throw CloudAIError.missingKey(provider: "Groq")
        }

        let asset = AVURLAsset(url: mediaURL)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)
        guard duration.isFinite, duration > 0 else {
            throw GroqSpeechError.noAudio
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaSupport-Groq-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let chunkCount = max(1, Int(ceil(duration / chunkDuration)))
        var allSegments: [SpeechSegment] = []
        var allWords: [SpeechWordTimestamp] = []
        var hasCompleteWordTiming = true
        var allSpeechActivity: [SpeechActivityInterval] = []

        for chunkIndex in 0..<chunkCount {
            try Task.checkCancellation()
            let start = Double(chunkIndex) * chunkDuration
            let length = min(chunkDuration, duration - start)
            let audioURL = tempDirectory
                .appendingPathComponent(String(format: "chunk-%03d.m4a", chunkIndex + 1))

            let preparingPercent = min(88, Int((Double(chunkIndex) / Double(chunkCount)) * 88))
            progress("MSM_PROGRESS:\(preparingPercent)")
            progress("… Chuẩn bị âm thanh \(chunkIndex + 1)/\(chunkCount)")

            try await exportAudio(
                from: asset,
                start: start,
                duration: length,
                to: audioURL
            )

            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize <= safeUploadBytes else {
                throw GroqSpeechError.chunkTooLarge
            }

            // Sound Analysis chạy local song song lúc Groq xử lý mạng. Nếu máy
            // không phân loại được, timing của Groq vẫn được giữ nguyên.
            async let speechActivity = detectSpeechActivity(
                in: audioURL,
                timelineOffset: start
            )
            progress("… Groq đang chép đoạn \(chunkIndex + 1)/\(chunkCount) · \(model.shortLabel)")
            let response = try await transcribe(
                audioURL: audioURL,
                sourceLanguage: sourceLanguage,
                model: model,
                key: key
            )

            let chunkWords = (response.words ?? []).map {
                SpeechWordTimestamp(
                    text: $0.word,
                    startSeconds: start + max(0, $0.start),
                    endSeconds: start + min(length, max($0.start + 0.02, $0.end))
                )
            }
            if SpeechWordTimingProcessor.hasMatchingTranscript(
                words: chunkWords,
                transcript: response.text
            ) {
                allWords.append(contentsOf: chunkWords)
            } else {
                hasCompleteWordTiming = false
            }

            let chunkSegments: [SpeechSegment]
            if let segments = response.segments, !segments.isEmpty {
                chunkSegments = segments.map {
                    SpeechSegment(
                        start: start + max(0, $0.start),
                        end: start + min(length, max($0.start + 0.05, $0.end)),
                        text: $0.text
                    )
                }
            } else {
                chunkSegments = [
                    SpeechSegment(
                        start: start,
                        end: start + length,
                        text: response.text
                    )
                ]
            }
            allSegments.append(contentsOf: chunkSegments)
            allSpeechActivity.append(contentsOf: await speechActivity)

            let completedPercent = min(92, Int((Double(chunkIndex + 1) / Double(chunkCount)) * 92))
            progress("MSM_PROGRESS:\(completedPercent)")
        }

        let segmentFallback = allSegments.enumerated().compactMap { offset, segment -> SRTSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SRTSegment(
                id: offset + 1,
                index: offset + 1,
                timing: SRTTimecode.makeTiming(start: segment.start, end: max(segment.start + 0.05, segment.end)),
                startSeconds: segment.start,
                endSeconds: max(segment.start + 0.05, segment.end),
                text: text
            )
        }
        // Waveform thường đã được Timeline dựng song song khi media được nạp.
        // Chỉ tái dùng cache; không khởi động thêm một lượt decode audio.
        let audioEvidence = await WaveformPeakService.cachedAudioEvidence(url: mediaURL)
        let localWordSegments = hasCompleteWordTiming
            ? SpeechWordTimingProcessor.makeSegments(
                from: allWords,
                languageCode: sourceLanguage,
                audioEvidence: audioEvidence
            )
            : []
        var wordSegments = localWordSegments
        if !localWordSegments.isEmpty, GroqModelPreferences.semanticCuePlanningEnabled {
            progress("… Đang tối ưu điểm ngắt theo ngữ cảnh")
            let semantic = await SemanticCueWorkflow.refine(
                words: allWords,
                localSegments: localWordSegments,
                languageCode: sourceLanguage,
                client: GroqAIClient()
            )
            if !semantic.segments.isEmpty { wordSegments = semantic.segments }
            if semantic.refinedBlockCount > 0 {
                progress("✓ Đã hiểu ngữ cảnh cho \(semantic.refinedBlockCount) cụm mơ hồ")
            }
            if semantic.fallbackBlockCount > 0 {
                progress("↩ Giữ cách ngắt local cho \(semantic.fallbackBlockCount) cụm không chắc chắn")
            }
        }
        let usesWordTiming = !wordSegments.isEmpty
        let rawSegments = usesWordTiming ? wordSegments : segmentFallback
        let burnStyle = SubtitleBurnStyle.load()
        let previewFrame = VideoPreviewFrame.classify(displaySize: VideoGeometryProbe.displaySize(for: mediaURL))
        let textWidth = Double(previewFrame.referencePixelSize.width) * Double(burnStyle.boxMaxWidthRatio) - 24
        let formatted = SubtitleTranscriptPostProcessor.format(
            rawSegments,
            sourceLanguage: sourceLanguage,
            style: wrapStyle,
            fontSize: burnStyle.fontSize,
            fontName: burnStyle.fontName,
            containerWidth: max(120, textWidth),
            maximumSpeechGap: usesWordTiming ? 0.45 : nil,
            coalescesSpeechChunks: !usesWordTiming,
            wordTimings: usesWordTiming ? allWords : []
        )
        let wordRetimed = usesWordTiming
            ? SpeechWordTimingProcessor.retime(formatted, using: allWords)
            : formatted
        let cleaned = SpeechTimingRefiner.refine(wordRetimed, using: allSpeechActivity)
        guard !cleaned.isEmpty else {
            throw GroqSpeechError.emptyTranscript
        }

        let srt = cleaned.enumerated().map { offset, segment in
            """
            \(offset + 1)
            \(segment.timing)
            \(segment.text)
            """
        }.joined(separator: "\n\n") + "\n"

        try srt.write(to: outputURL, atomically: true, encoding: .utf8)
        progress("MSM_PROGRESS:100")
    }

    private static func detectSpeechActivity(
        in audioURL: URL,
        timelineOffset: Double
    ) async -> [SpeechActivityInterval] {
        do {
            return try await AppleSpeechActivityDetector.detect(in: audioURL).map {
                SpeechActivityInterval(
                    startSeconds: timelineOffset + $0.startSeconds,
                    endSeconds: timelineOffset + $0.endSeconds,
                    confidence: $0.confidence
                )
            }
        } catch {
            return []
        }
    }

    private static func exportAudio(
        from asset: AVAsset,
        start: Double,
        duration: Double,
        to outputURL: URL
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw GroqSpeechError.cannotPrepareAudio
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: exporter.error ?? GroqSpeechError.cannotPrepareAudio
                    )
                }
            }
        }
    }

    private static func transcribe(
        audioURL: URL,
        sourceLanguage: String,
        model: GroqSpeechModel,
        key: String
    ) async throws -> GroqTranscriptionResponse {
        let boundary = "MediaSupportBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendFormField(name: "model", value: model.rawValue, boundary: boundary)
        body.appendFormField(name: "response_format", value: "verbose_json", boundary: boundary)
        body.appendFormField(name: "temperature", value: "0", boundary: boundary)
        body.appendFormField(
            name: "timestamp_granularities[]",
            value: "segment",
            boundary: boundary
        )
        body.appendFormField(
            name: "timestamp_granularities[]",
            value: "word",
            boundary: boundary
        )

        let normalizedLanguage = AppleSRTTranslator.normalizeLangCode(sourceLanguage)
        if normalizedLanguage != "auto", !normalizedLanguage.isEmpty {
            body.appendFormField(
                name: "language",
                value: normalizedLanguage,
                boundary: boundary
            )
        }

        let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])
        body.appendFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/mp4",
            data: audioData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let data = try await CloudAIHTTPTransport.perform(
            request,
            fallbackMessage: "Groq từ chối yêu cầu chép lời.",
            responseObserver: { response in
                ProviderUsageStore.captureGroqHeaders(response, modelID: model.rawValue)
            }
        )
        do {
            return try JSONDecoder().decode(GroqTranscriptionResponse.self, from: data)
        } catch {
            throw CloudAIError.invalidResponse
        }
    }
}

private struct GroqTranscriptionResponse: Decodable {
    struct Segment: Decodable {
        let start: Double
        let end: Double
        let text: String
    }

    struct Word: Decodable {
        let word: String
        let start: Double
        let end: Double
    }

    let text: String
    let segments: [Segment]?
    let words: [Word]?
}

private struct SpeechSegment: Sendable {
    let start: Double
    let end: Double
    let text: String
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

enum GroqSpeechError: LocalizedError {
    case noAudio
    case cannotPrepareAudio
    case chunkTooLarge
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .noAudio:
            "Không đọc được track âm thanh trong media."
        case .cannotPrepareAudio:
            "Không thể chuẩn bị âm thanh để gửi Groq."
        case .chunkTooLarge:
            "Một đoạn âm thanh vượt giới hạn upload Groq 25 MB."
        case .emptyTranscript:
            "Groq không nhận diện được lời nói trong media."
        }
    }
}
