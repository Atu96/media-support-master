import AVFoundation
import Foundation
import Darwin

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private final class StubAIClient: CloudAIClient {
    var response: String
    private(set) var requests: [CloudAIGenerationRequest] = []

    init(response: String) {
        self.response = response
    }

    func generate(_ request: CloudAIGenerationRequest) async throws -> String {
        requests.append(request)
        return response
    }
}

private struct TestTranslationRequest: Decodable {
    let id: Int
    let text: String
}

private final class TranslationEchoStub: CloudAIClient {
    private(set) var requests: [CloudAIGenerationRequest] = []

    func generate(_ request: CloudAIGenerationRequest) async throws -> String {
        requests.append(request)
        guard let inputRange = request.user.range(of: "INPUT:\n") else {
            throw TestFailure(description: "prompt dịch thiếu INPUT")
        }
        let input = String(request.user[inputRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = try JSONDecoder().decode([TestTranslationRequest].self, from: Data(input.utf8))
        let translations = source.map { ["id": $0.id, "text": "VI \($0.id)"] }
        let body = try JSONSerialization.data(withJSONObject: ["translations": translations])
        return String(decoding: body, as: UTF8.self)
    }
}

private final class MissingThenRecoveringTranslationStub: CloudAIClient {
    private(set) var requests: [CloudAIGenerationRequest] = []

    func generate(_ request: CloudAIGenerationRequest) async throws -> String {
        requests.append(request)
        if requests.count == 1 {
            return #"{"translations":[{"id":0,"text":"Một"}]}"#
        }
        guard let inputRange = request.user.range(of: "INPUT:\n") else {
            throw TestFailure(description: "prompt bổ sung thiếu INPUT")
        }
        let input = String(request.user[inputRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = try JSONDecoder().decode([TestTranslationRequest].self, from: Data(input.utf8))
        let translations = source.map { ["id": $0.id, "text": $0.id == 1 ? "Hai" : "Một"] as [String: Any] }
        let body = try JSONSerialization.data(withJSONObject: ["translations": translations])
        return String(decoding: body, as: UTF8.self)
    }
}

@main
enum MediaSupportCoreTests {
    private static var passed = 0
    private static var failed = 0

    static func main() async {
        run("SRT timecode chính xác", testTimecode)
        run("Cài mới English, nâng cấp giữ lựa chọn ngôn ngữ", testAppLanguageSelection)
        run("Support chỉ dùng URL HTTPS cố định không kèm dữ liệu", testSupportLink)
        run("App di chuyển vẫn tìm script nhúng, giữ override và TEST checkout", testRuntimeRoot)
        run("SRT parse + render giữ nội dung", testSRTDocument)
        run("SRT editor giữ timing hợp lệ", testSRTEditor)
        run("Chọn nhiều cue và range liền kề ổn định", testTimelineCueSelection)
        run("Wrap sửa từ Latin bị STT tách ký tự", testSpacedLatinNormalization)
        run("Đổi chữ/dòng không chém từ hoặc bỏ ngắt dấu câu", testPunctuationSafeWrap)
        run("Layout native đo glyph và giữ hợp đồng một/hai dòng", testNativeSubtitleLayout)
        run("Layout native giữ manual break và grapheme đa ngôn ngữ", testNativeSubtitleLayoutLanguages)
        run("Một dòng đa ngôn ngữ tránh cắt cụm và cue đuôi", testMultilingualSingleLineBreakScoring)
        run("Hai dòng đa ngôn ngữ dùng optimizer toàn chuỗi", testMultilingualTwoLineBreakScoring)
        run("Thiếu dấu câu vẫn ngắt theo cụm đa ngôn ngữ", testUnpunctuatedMultilingualLayout)
        run("Word không dấu dùng ngữ cảnh và chỉ nhận pause đã khớp", testUnpunctuatedWordPlanning)
        run("Nhật giữ nguyên bố cục golden trước lớp ngữ cảnh mới", testJapaneseLayoutGolden)
        run("Fallback layout không chẻ token provider dài", testVerifiedTokenEmergencyBoundary)
        await runAsync("Đổi bố cục chạy nền, hủy worker và chỉ nhận yêu cầu cuối", testLayoutReflowLifecycle)
        run("Reflow 9 phút đa ngôn ngữ giữ text/timing và phép đo một cue", testLongTranscriptReflow)
        run("Subtitle QC phát hiện tràn, tốc độ và timing nhưng không sửa cue", testSubtitleQualityAnalyzer)
        run("Chép lời dài tách cue theo 1/2 dòng, giữ timing", testTranscriptPostProcessor)
        run("Chép lời Việt gom mảnh STT thành cue đọc được", testVietnameseSpeechChunkCoalescing)
        run("Dọn cue gom mảnh ngắn qua khoảng lặng ngắn", testShortGapSpeechChunkCoalescing)
        run("Vùng lời nói tinh chỉnh mép cue nhưng không tạo text", testSpeechTimingRefiner)
        run("Không có speech thì giữ nguyên timing provider", testSpeechTimingFallback)
        run("Khoảng lặng thật được giữ giữa hai cue", testSpeechTimingSilenceGap)
        run("Word timestamp giữ pause thành ranh giới cue", testWordTimestampGrouping)
        run("Pause thích ứng đa ngôn ngữ giữ micro-pause và hard silence", testAdaptiveMultilingualPausePlanning)
        run("Năng lượng waveform chỉ nâng pause mềm có bằng chứng", testCachedWaveformSilencePlanning)
        run("Cue ngắn liền kề tự gộp khi layout và timing an toàn", testSafeAdjacentCueMerging)
        run("Layout không gộp ngược qua giới hạn pause của word timing", testRequiredWordPauseSurvivesLayout)
        run("Large V3 nói liên tục vẫn chia cue dưới sáu giây", testWordTimestampContinuousSpeechPlanning)
        run("Layout không ghép ngược ranh giới word timing", testWordTimestampBoundariesSurviveLayout)
        run("Cue layout nhận đúng mép thời gian từng từ", testWordTimestampRetime)
        run("Retime từ chối transcript cùng độ dài nhưng sai thứ tự", testWordTimestampRetimeRejectsReorderedText)
        run("Word timestamp lệch text phải fallback an toàn", testWordTimestampFallback)
        run("Word timestamp CJK ghép không chèn khoảng trắng", testWordTimestampCJK)
        await runAsync("Semantic cue chỉ đổi boundary và giữ nguyên mọi từ", testSemanticCuePlanning)
        await runAsync("Semantic cue sai phải fallback nguyên local", testSemanticCueFallback)
        await runAsync("Undo/Redo subtitle có giới hạn và không mất thứ tự", testBoundedSubtitleEditHistory)
        await runAsync("Waveform native giữ duration audio và có peak", testWaveformPeakService)
        run("Quy tắc tên/path dự án ổn định", testProjectPaths)
        run("TTS ưu tiên Google, giữ Eleven v3 và Apple Offline", testDubbingProviderCatalog)
        run("Dubbing fingerprint và fit cue ổn định", testDubbingModels)
        run("Nút lồng cue chỉ bật khi selection và provider hợp lệ", testDubbingToolbarAvailability)
        run("Chọn giọng Maziao luôn đồng bộ đúng mô hình", testMaziaoVoiceSelectionPolicy)
        run("Catalog giọng nhóm và tìm theo tên quốc gia", testDubbingVoiceCatalogGrouping)
        run("Google và ElevenLabs decode catalog giọng phân trang", testCloudVoiceCatalogDecoders)
        run("Cache DUB đo dung lượng thật và không đếm đôi hard-link", testDubbingCacheUsage)
        run("Cache giọng tái dùng qua ID/xuống dòng, tách audio ghép và xóa", testDubbingSpeechReuse)
        run("ElevenLabs gửi đúng tốc độ, giữ chữ và mô hình", testElevenLabsGenerationSpeed)
        await runAsync("Maziao phục hồi receipt sau lỗi/hủy/restart không submit lại", testMaziaoTaskRecovery)
        await runAsync("Hàng đợi DUB giới hạn hai việc và dọn khi hủy/lỗi", testDubbingRenderQueue)
        await runAsync("MP3 gốc mở/phát/ghép được và không giải nén cache", testDubbingCompressedCache)
        await runAsync("Cache duration giữ hard-link và bỏ metadata khi tệp đổi", testDubbingDurationCache)
        await runAsync("Gộp cue giữ DUB phía sau và ghép audio cục bộ", testDubbingCueMergePreservation)
        run("Maziao fixture giải mã account, voice và submit ổn định", testMaziaoResponseFixtures)
        run("Maziao fixture giữ trạng thái pending/completed và URL audio", testMaziaoTaskStatusFixtures)
        run("Maziao request khớp tài liệu API đầy đủ", testMaziaoSubmitRequestSchema)
        run("Maziao lỗi validation hiển thị đúng trường bị từ chối", testMaziaoValidationErrorMessage)
        run("Maziao errors envelope giữ lý do và HTTP status", testMaziaoErrorEnvelope)
        run("Maziao error không phản chiếu input và có giới hạn", testMaziaoErrorBoundary)
        run("Maziao metadata phân trang giữ total, limit và offset", testMaziaoVoicePageMetadata)
        run("Maziao length kiểm tra biên và không sửa nội dung", testMaziaoLengthBoundary)
        run("Maziao batch giữ thứ tự và xử lý nhóm cuối ngắn", testMaziaoBatchPlanning)
        run("Maziao multiParts giữ từng câu và cấu hình", testMaziaoBatchRequest)
        run("Maziao multiParts kiểm tra đủ tệp trước gán cue", testMaziaoBatchResults)
        run("Maziao polling thích ứng không hết hạn sớm", testMaziaoPollingPolicy)
        await runAsync("Audio cloud đóng file trước khi phát ngay", testCloudAudioImmediatePlayback)
        run("Maziao response sai schema phải từ chối an toàn", testMaziaoInvalidResponse)
        run("Localization format số nguyên không crash", testLocalizedNumericFormatting)
        await runAsync("Dịch AI bằng client giả — không gọi API", testFakeTranslation)
        await runAsync("Dịch SRT dài tự chia phần và ráp đúng cue", testLongTranslationChunks)
        await runAsync("AI bỏ sót cue được bổ sung riêng", testIncompleteTranslationRecovery)
        await runAsync("AI trả thiếu block không ghi file", testIncompleteTranslation)
        await runAsync("Tóm tắt AI bằng client giả — không gọi API", testFakeSummary)
        run("Groq phân biệt truncated và JSON-mode retry", testGroqResponsePolicy)
        run("Groq kiểm tra key bằng catalog mô hình", testGroqConnectionResponse)
        run("Groq đọc đúng header hạn mức từ inference", testGroqRateLimitHeaders)
        await runAsync("Groq chỉ chờ và thử lại 429 có giới hạn", testGroqRateLimitRetry)
        await runAsync("Dịch giữ code fence trong nội dung và nhận schema tương đương", testTranslationVariants)
        await runAsync("Dịch lỗi định dạng chia nhỏ có giới hạn", testTranslationSchemaRepair)
        await runAsync("Dịch từ chối ID trùng/lạ và bảo vệ file", testTranslationRejectsAmbiguousIDs)
        await runAsync("Dịch không retry quota/auth và giữ file khi hủy", testTranslationNoUnsafeRetry)

        print("")
        print("Kết quả: \(passed) đạt · \(failed) lỗi")
        if failed > 0 {
            exit(1)
        }
    }

    private static func run(_ name: String, _ test: () throws -> Void) {
        do {
            try test()
            passed += 1
            print("✓ \(name)")
        } catch {
            failed += 1
            print("✗ \(name): \(error)")
        }
    }

    private static func testGroqConnectionResponse() throws {
        let valid = Data(#"{"object":"list","data":[{"id":"model-a"},{"id":"model-b"}]}"#.utf8)
        let modelCount = try GroqConnectionResponseDecoder.modelCount(from: valid)
        try expect(
            modelCount == 2,
            "catalog Groq hợp lệ phải xác nhận được key"
        )

        let invalid = Data(#"{"object":"list","models":[]}"#.utf8)
        do {
            _ = try GroqConnectionResponseDecoder.modelCount(from: invalid)
            throw TestFailure(description: "catalog Groq thiếu data phải bị từ chối")
        } catch is DecodingError {
            // Expected: a 2xx response still must match Groq's documented model-list schema.
        }
    }

    private static func testGroqRateLimitHeaders() throws {
        let values = try require(
            GroqRateLimitHeaderDecoder.decode([
                "X-RateLimit-Limit-Requests": "1000",
                "x-ratelimit-remaining-requests": " 999 ",
                "x-ratelimit-limit-tokens": "8000",
                "x-ratelimit-remaining-tokens": "7927",
                "x-ratelimit-reset-requests": "1m26.4s",
                "x-ratelimit-reset-tokens": "547ms"
            ]),
            "header inference Groq hợp lệ phải decode được"
        )
        try expect(values.requestLimit == 1000, "đọc sai request limit")
        try expect(values.remainingRequests == 999, "đọc sai request remaining")
        try expect(values.tokenLimit == 8000, "đọc sai token limit")
        try expect(values.remainingTokens == 7927, "đọc sai token remaining")
        try expect(values.requestReset == "1m26.4s", "đọc sai request reset")
        try expect(values.tokenReset == "547ms", "đọc sai token reset")
        try expect(
            GroqRateLimitHeaderDecoder.decode(["content-type": "application/json"]) == nil,
            "response model-list không có rate-limit không được tạo snapshot rỗng"
        )
    }

    private static func testGroqRateLimitRetry() async throws {
        try expect(
            GroqRateLimitRetryPolicy.retryAfterSeconds(" 2.5 ") == 2.5,
            "phải đọc retry-after số giây"
        )
        try expect(
            GroqRateLimitRetryPolicy.retryAfterSeconds("tomorrow") == nil,
            "retry-after không hợp lệ không được coi là thời gian chờ"
        )
        try expect(
            GroqRateLimitRetryPolicy.retryAfterSeconds("1e300") == 86_400,
            "retry-after rất lớn phải được chặn trước khi hiển thị"
        )
        try expect(
            GroqRateLimitRetryPolicy.waitSeconds(retryAfter: 120, retryIndex: 0) == nil,
            "không được chờ quá lâu ở rate-limit dài"
        )

        var calls = 0
        var waits: [Double] = []
        let value: String = try await GroqRateLimitRetryPolicy.run(
            progress: nil,
            sleep: { waits.append($0) }
        ) { _ in
            calls += 1
            if calls < 3 { throw CloudAIError.rateLimited(retryAfterSeconds: 2) }
            return "ok"
        }
        try expect(value == "ok" && calls == 3, "429 chỉ được thử lại tối đa hai lần")
        try expect(waits == [2.5, 2.5], "phải dùng retry-after của provider")

        calls = 0
        do {
            let _: String = try await GroqRateLimitRetryPolicy.run(
                progress: nil,
                sleep: { _ in }
            ) { _ in
                calls += 1
                throw CloudAIError.http(status: 401, message: "fixture")
            }
            throw TestFailure(description: "401 không được báo thành công")
        } catch let error as CloudAIError {
            guard case .http(status: 401, _) = error else {
                throw TestFailure(description: "401 bị đổi thành lỗi khác")
            }
        }
        try expect(calls == 1, "401 không được retry")

        calls = 0
        do {
            let _: String = try await GroqRateLimitRetryPolicy.run(
                progress: nil,
                sleep: { _ in }
            ) { _ in
                calls += 1
                throw CloudAIError.rateLimited(retryAfterSeconds: 1)
            }
            throw TestFailure(description: "429 lặp lại không được báo thành công")
        } catch let error as CloudAIError {
            guard case .rateLimited = error else {
                throw TestFailure(description: "429 lặp lại bị đổi thành lỗi khác")
            }
        }
        try expect(calls == 3, "429 lặp lại không được tạo vòng thử vô hạn")
    }

    private static func runAsync(
        _ name: String,
        _ test: () async throws -> Void
    ) async {
        do {
            try await test()
            passed += 1
            print("✓ \(name)")
        } catch {
            failed += 1
            print("✗ \(name): \(error)")
        }
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        guard try condition() else {
            throw TestFailure(description: message)
        }
    }

    private static func segment(
        id: Int,
        start: Double,
        end: Double,
        text: String
    ) -> SRTSegment {
        SRTSegment(
            id: id,
            index: id,
            timing: SRTTimecode.makeTiming(start: start, end: end),
            startSeconds: start,
            endSeconds: end,
            text: text
        )
    }

    private static func word(_ text: String, _ start: Double, _ end: Double) -> SpeechWordTimestamp {
        SpeechWordTimestamp(text: text, startSeconds: start, endSeconds: end)
    }

    private static func testRuntimeRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout")
        let bundle = checkout.appendingPathComponent("dist/test/App.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        let runtime = resources.appendingPathComponent("Runtime")
        let home = root.appendingPathComponent("home")
        func resolve(_ override: String? = nil) -> URL {
            AppRuntimeRootResolver.resolve(configured: override, bundleURL: bundle, resourceURL: resources, home: home)
        }
        try expect(resolve().path == home.appendingPathComponent("Documents/Media Support App").path, "legacy fallback sai")
        for candidate in [checkout, runtime] {
            try FileManager.default.createDirectory(at: candidate.appendingPathComponent("scripts"), withIntermediateDirectories: true)
            try Data().write(to: candidate.appendingPathComponent("scripts/common.sh"))
            try expect(resolve().path == candidate.path, "script nhúng phải ưu tiên hơn checkout")
        }
        let override = root.appendingPathComponent("custom")
        try expect(resolve(override.path).path == override.path, "APP_ROOT phải thắng runtime nhúng")
        let moved = root.appendingPathComponent("Applications/App.app")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: bundle, to: moved)
        let movedResources = moved.appendingPathComponent("Contents/Resources")
        let actual = AppRuntimeRootResolver.resolve(configured: nil, bundleURL: moved, resourceURL: movedResources, home: home)
        try expect(actual.path == movedResources.appendingPathComponent("Runtime").path, "app di chuyển vẫn phải dùng script nhúng")
    }

    private static func testAppLanguageSelection() throws {
        try expect(AppLanguageSelectionPolicy.resolve(saved: nil, legacy: nil) == "en", "cài mới không English")
        for code in AppLanguageSelectionPolicy.validCodes {
            try expect(AppLanguageSelectionPolicy.resolve(saved: code, legacy: "en") == code,
                       "ghi đè ngôn ngữ đã lưu: \(code)")
            try expect(AppLanguageSelectionPolicy.resolve(saved: nil, legacy: code) == code,
                       "mất lựa chọn legacy: \(code)")
        }
        try expect(AppLanguageSelectionPolicy.resolve(saved: "invalid", legacy: "vi") == "vi", "mất legacy hợp lệ")
        try expect(AppLanguageSelectionPolicy.resolve(saved: "invalid", legacy: "invalid") == "en", "fallback không English")
    }

    private static func testSupportLink() throws {
        let url = AppSupportLink.url
        try expect(url.absoluteString == "https://ko-fi.com/atu1202" && url.scheme == "https"
            && url.query == nil && url.fragment == nil && url.user == nil && url.password == nil,
                   "Support gửi URL không đúng hoặc kèm dữ liệu")
    }

    private static func testTimecode() throws {
        try expect(SRTTimecode.parse("01:02:03,456") == 3_723.456, "parse mili-giây sai")
        try expect(SRTTimecode.formatPrecise(62.345) == "00:01:02,345", "format chính xác sai")
        try expect(
            SRTTimecode.makeTiming(start: 1.2, end: 3.45)
                == "00:00:01,200 --> 00:00:03,450",
            "timing SRT sai"
        )
    }

    private static func testLocalizedNumericFormatting() throws {
        try expect(L10n.format("Dịch %d%%", 100) == "Dịch 100%", "format phần trăm số nguyên sai")
        try expect(
            L10n.format("%d / %d cue đã có giọng", 2, 5) == "2 / 5 cue đã có giọng",
            "format hai số nguyên sai"
        )
        try expect(
            L10n.format("%d dự án · %@", 3, "12 MB") == "3 dự án · 12 MB",
            "format số nguyên + chuỗi sai"
        )
        try expect(
            L10n.format("Phòng thủ legacy %@", 100) == "Phòng thủ legacy 100",
            "scalar legacy với %@ vẫn có thể crash"
        )
    }

    private static func testSRTDocument() throws {
        let source = """
        1
        00:00:01,200 --> 00:00:03,450
        Hello
        world

        2
        00:00:04,000 --> 00:00:05,250
        Goodbye
        """
        let segments = SRTDocument.parseSegments(source)
        try expect(segments.count == 2, "phải đọc được 2 cue")
        try expect(segments[0].text == "Hello\nworld", "mất dòng subtitle")
        try expect(segments[1].endSeconds == 5.25, "mất mili-giây")

        let rendered = SRTDocument.renderSRT(segments)
        let reparsed = SRTDocument.parseSegments(rendered)
        try expect(reparsed.count == segments.count, "render rồi parse bị mất cue")
        try expect(reparsed.map(\.text) == segments.map(\.text), "render đổi nội dung")

        let reading = SRTDocument.renderTXT([
            SRTSegment(id: 1, index: 1, timing: SRTTimecode.makeTiming(start: 0, end: 1), startSeconds: 0, endSeconds: 1, text: "Đây là câu đầu."),
            SRTSegment(id: 2, index: 2, timing: SRTTimecode.makeTiming(start: 1, end: 2), startSeconds: 1, endSeconds: 2, text: "Nó nối từ cue kế tiếp."),
            SRTSegment(id: 3, index: 3, timing: SRTTimecode.makeTiming(start: 4, end: 5), startSeconds: 4, endSeconds: 5, text: "Đây là đoạn mới."),
        ])
        try expect(!reading.contains("-->"), "TXT đọc không được chứa timecode cue")
        try expect(reading.contains("Đây là câu đầu. Nó nối từ cue kế tiếp.\n\nĐây là đoạn mới."), "TXT phải nối cue và tạo đoạn theo khoảng nghỉ")
    }

    private static func testSRTEditor() throws {
        let segments = [
            SRTSegment(
                id: 1,
                index: 1,
                timing: SRTTimecode.makeTiming(start: 1, end: 3),
                startSeconds: 1,
                endSeconds: 3,
                text: "Hello"
            ),
            SRTSegment(
                id: 2,
                index: 2,
                timing: SRTTimecode.makeTiming(start: 3.2, end: 5),
                startSeconds: 3.2,
                endSeconds: 5,
                text: "world"
            )
        ]

        let moved = try require(
            SRTSegmentEditor.move(in: segments, id: 1, delta: -5),
            "không move được cue"
        )
        try expect(moved[0].startSeconds == 0, "move âm không clamp về 0")
        try expect(moved[0].endSeconds == 2, "move không giữ duration")

        let merged = try require(
            SRTSegmentEditor.mergeAdjacent(in: segments, ids: [1, 2]),
            "không merge được cue kề nhau"
        )
        try expect(merged.count == 1, "merge không giảm số cue")
        try expect(merged[0].text == "Hello\nworld", "merge mất nội dung")
        try expect(merged[0].endSeconds == 5, "merge đổi span cuối")

        let fourCues = segments + [
            SRTSegment(
                id: 3,
                index: 3,
                timing: SRTTimecode.makeTiming(start: 5.1, end: 6),
                startSeconds: 5.1,
                endSeconds: 6,
                text: "again"
            ),
            SRTSegment(
                id: 4,
                index: 4,
                timing: SRTTimecode.makeTiming(start: 6.2, end: 7),
                startSeconds: 6.2,
                endSeconds: 7,
                text: "later"
            )
        ]
        let mergedMany = try require(
            SRTSegmentEditor.mergeAdjacent(in: fourCues, ids: [1, 2, 3]),
            "không merge được từ ba cue kề nhau"
        )
        try expect(mergedMany.count == 2, "merge nhiều cue giảm sai số lượng")
        try expect(mergedMany[0].text == "Hello\nworld\nagain", "merge nhiều cue làm sai thứ tự chữ")
        try expect(mergedMany[0].startSeconds == 1 && mergedMany[0].endSeconds == 6, "merge nhiều cue đổi span tổng")
        try expect(mergedMany.map(\.id) == [1, 2], "merge nhiều cue phải đánh lại id liên tục")
        try expect(
            SRTSegmentEditor.mergeAdjacent(in: fourCues, ids: [1, 3]) == nil,
            "không được merge các cue không liền kề"
        )

        let deletedMany = try require(
            SRTSegmentEditor.delete(in: fourCues, ids: [2, 3]),
            "không xóa được nhiều cue đã chọn"
        )
        try expect(deletedMany.map(\.text) == ["Hello", "later"], "xóa nhiều cue làm sai thứ tự")
        try expect(deletedMany.map(\.id) == [1, 2], "xóa nhiều cue phải đánh lại id liên tục")
        let deletedAll = try require(
            SRTSegmentEditor.delete(in: fourCues, ids: Set(fourCues.map(\.id))),
            "phải cho phép xóa toàn bộ cue"
        )
        try expect(deletedAll.isEmpty, "xóa toàn bộ cue phải tạo trạng thái rỗng hợp lệ")
    }

    private static func testSpacedLatinNormalization() throws {
        try expect(
            SubtitleWrapStyle.flattenToOneLine("someone a b o a r d this ship")
                == "someone aboard this ship",
            "không gộp từ Latin bị tách ký tự"
        )
        try expect(
            SubtitleWrapStyle.flattenToOneLine("U k r a i n e has no navy")
                == "Ukraine has no navy",
            "không gộp từ Latin có chữ đầu viết hoa"
        )
        try expect(
            SubtitleWrapStyle.flattenToOneLine("AI and U S A are kept")
                == "AI and U S A are kept",
            "không được gộp acronym ngắn hợp lệ"
        )
    }

    private static func testTimelineCueSelection() throws {
        let orderedIDs = [1, 2, 3, 4, 5]
        var selection = TimelineCueSelection()
        selection.select(id: 2, intent: .replace, orderedIDs: orderedIDs)
        selection.select(id: 4, intent: .range, orderedIDs: orderedIDs)
        try expect(selection.selectedIDs == [2, 3, 4], "Shift-click phải chọn trọn dải từ anchor")
        try expect(selection.primaryID == 4, "range phải giữ cue vừa click làm primary")
        try expect(selection.canMerge(orderedIDs: orderedIDs), "dải liền kề phải cho phép gộp")

        selection.select(id: 3, intent: .toggle, orderedIDs: orderedIDs)
        try expect(selection.selectedIDs == [2, 4], "Cmd-click phải bỏ đúng một cue")
        try expect(!selection.canMerge(orderedIDs: orderedIDs), "dải có lỗ không được phép gộp")

        selection.select(id: 3, intent: .toggle, orderedIDs: orderedIDs)
        selection.reconcile(orderedIDs: [1, 2, 3])
        try expect(selection.selectedIDs == [2, 3], "reconcile phải bỏ id không còn tồn tại")

        selection.replace(with: [1, 3], orderedIDs: orderedIDs)
        try expect(selection.selectedIDs == [1, 3], "quét vùng phải thay đúng tập cue")
        try expect(selection.primaryID == 1, "quét vùng phải chọn primary ổn định theo thứ tự timeline")
        try expect(!selection.canMerge(orderedIDs: orderedIDs), "quét cue rời nhau không được bật gộp")

        selection.selectAll(orderedIDs: orderedIDs)
        try expect(selection.count == orderedIDs.count, "Cmd A phải chọn toàn bộ cue")
        try expect(selection.canDelete(totalCueCount: orderedIDs.count), "phải cho phép xóa toàn bộ cue đã chọn")
    }

    private static func testTranscriptPostProcessor() throws {
        let longEnglish = SRTSegment(
            id: 1,
            index: 1,
            timing: SRTTimecode.makeTiming(start: 10, end: 16),
            startSeconds: 10,
            endSeconds: 16,
            text: "This is a deliberately long English subtitle that must become several readable cues without cutting any individual word in half."
        )
        var oneLine = SubtitleWrapStyle.appDefault
        oneLine.maxLines = 1
        oneLine.maxCharsPerLine = 24
        let english = SubtitleTranscriptPostProcessor.format(
            [longEnglish], sourceLanguage: "en", style: oneLine, fontSize: 54
        )
        try expect(english.count > 1, "cue Latin cực dài vẫn cần trần an toàn")
        try expect(english.first?.startSeconds == 10, "tách cue làm đổi start")
        try expect(english.last?.endSeconds == 16, "tách cue làm đổi end")
        for (index, cue) in english.enumerated() {
            try expect(!cue.text.contains("\n"), "mode 1 dòng vẫn có newline")
            try expect(cue.text.count <= 56, "cue Latin 1 dòng vượt trần an toàn")
            if index > 0 {
                try expect(abs(english[index - 1].endSeconds - cue.startSeconds) < 0.001, "cue tách phải liền timing")
            }
        }
        try expect(
            english.contains { $0.text.count > 24 },
            "mode 1 dòng Latin vẫn đang cắt cứng theo Chữ/dòng"
        )

        let naturalVietnamese = SRTSegment(
            id: 1,
            index: 1,
            timing: SRTTimecode.makeTiming(start: 0, end: 3.2),
            startSeconds: 0,
            endSeconds: 3.2,
            text: "Mình sinh ra và lớn lên trong một vùng quê nghèo thuộc miền Tây Nam Bộ."
        )
        var vietnameseOneLine = SubtitleWrapStyle.appDefault
        vietnameseOneLine.maxLines = 1
        vietnameseOneLine.maxCharsPerLine = 24
        let naturalVietnameseResult = SubtitleTranscriptPostProcessor.format(
            [naturalVietnamese], sourceLanguage: "vi", style: vietnameseOneLine, fontSize: 54
        )
        try expect(
            naturalVietnameseResult.count == 2,
            "1 dòng Việt phải giữ cụm tự nhiên, chỉ tách ở trần an toàn"
        )
        try expect(
            naturalVietnameseResult.first?.text.count ?? 0 > 24,
            "1 dòng Việt vẫn bị chặt cụt tại số Chữ/dòng"
        )

        let japanese = SRTSegment(
            id: 1,
            index: 1,
            timing: SRTTimecode.makeTiming(start: 0, end: 8),
            startSeconds: 0,
            endSeconds: 8,
            text: "これは日本語の長い字幕です。読みやすく二行以内に整えて必要なら安全に複数のキューへ分割します。"
        )
        var twoLines = SubtitleWrapStyle.appDefault
        twoLines.maxLines = 2
        twoLines.maxCharsPerLine = 12
        let ja = SubtitleTranscriptPostProcessor.format(
            [japanese], sourceLanguage: "ja", style: twoLines, fontSize: 54
        )
        try expect(ja.count > 1, "日本語の長い cue phải tách")
        try expect(ja.allSatisfy { $0.text.split(separator: "\n", omittingEmptySubsequences: false).count <= 2 }, "mode 2 dòng vượt số dòng")
        try expect(ja.first?.startSeconds == 0 && ja.last?.endSeconds == 8, "日本語 tách làm đổi tổng timing")

        let vietnameseFragments = [
            SRTSegment(id: 1, index: 1, timing: SRTTimecode.makeTiming(start: 12, end: 15), startSeconds: 12, endSeconds: 15, text: "Bạn đang bước một chân vào chiếc bẫy tâm lý tàn khốc nhất của thị"),
            SRTSegment(id: 2, index: 2, timing: SRTTimecode.makeTiming(start: 15, end: 16), startSeconds: 15, endSeconds: 16, text: "trường"),
        ]
        let vi = SubtitleTranscriptPostProcessor.format(
            vietnameseFragments, sourceLanguage: "vi", style: SubtitleWrapStyle(maxCharsPerLine: 33), fontSize: 54
        )
        try expect(!vi.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "trường" }, "không được để lại cue một từ ở cuối câu")
        try expect(SubtitleWrapStyle.flattenToOneLine(vi.map(\.text).joined(separator: " ")).contains("thị trường"), "phải giữ cụm từ bị STT tách mốc")
        try expect(vi.first?.startSeconds == 12 && vi.last?.endSeconds == 16, "ghép mảnh ngắn làm đổi span timing")
    }

    private static func testVietnameseSpeechChunkCoalescing() throws {
        let fragments = [
            SRTSegment(id: 1, index: 1, timing: SRTTimecode.makeTiming(start: 0, end: 0.8), startSeconds: 0, endSeconds: 0.8, text: "Kính thưa quý vị,"),
            SRTSegment(id: 2, index: 2, timing: SRTTimecode.makeTiming(start: 0.8, end: 3.2), startSeconds: 0.8, endSeconds: 3.2, text: "mùa báo cáo tài chính bán niên quý 2 năm 2026 vừa chính thức khép lại"),
            SRTSegment(id: 3, index: 3, timing: SRTTimecode.makeTiming(start: 3.2, end: 5.6), startSeconds: 3.2, endSeconds: 5.6, text: "với những khoản lợi nhuận nghìn tỷ lấp lánh từ hệ thống ngân hàng."),
        ]
        let formatted = SubtitleTranscriptPostProcessor.format(
            fragments,
            sourceLanguage: "vi",
            style: SubtitleWrapStyle.appDefault,
            fontSize: 54
        )
        try expect(
            !formatted.contains { SubtitleWrapStyle.flattenToOneLine($0.text) == "Kính thưa quý vị," },
            "không để lại lời xưng hô thành một cue lẻ"
        )
        let rendered = SubtitleWrapStyle.flattenToOneLine(formatted.map(\.text).joined(separator: " "))
        try expect(rendered.contains("Kính thưa quý vị, mùa báo cáo tài chính"), "gom mảnh làm mất thứ tự câu Việt")
        try expect(formatted.first?.startSeconds == 0 && formatted.last?.endSeconds == 5.6, "gom mảnh làm đổi span timing gốc")
        for index in formatted.indices.dropFirst() {
            try expect(abs(formatted[index - 1].endSeconds - formatted[index].startSeconds) < 0.001, "cue sau khi gom phải liền timing")
        }
    }

    private static func testShortGapSpeechChunkCoalescing() throws {
        let fragments = [
            SRTSegment(id: 1, index: 1, timing: SRTTimecode.makeTiming(start: 0, end: 1.0), startSeconds: 0, endSeconds: 1.0, text: "Miền Tây, một thời di dân"),
            SRTSegment(id: 2, index: 2, timing: SRTTimecode.makeTiming(start: 1.7, end: 3.0), startSeconds: 1.7, endSeconds: 3.0, text: "Tác giả, thích phước tiến"),
        ]
        let formatted = SubtitleTranscriptPostProcessor.format(
            fragments, sourceLanguage: "vi", style: SubtitleWrapStyle(maxCharsPerLine: 33), fontSize: 54
        )
        let rendered = SubtitleWrapStyle.flattenToOneLine(formatted.map(\.text).joined(separator: " "))
        try expect(rendered.contains("Miền Tây, một thời di dân Tác giả"), "gap ngắn giữa hai mảnh thoại phải được gom")
        try expect(!formatted.contains { SubtitleWrapStyle.flattenToOneLine($0.text) == "Tác giả, thích phước tiến" }, "không để lại mảnh ngắn sau gap 0.7s")
        try expect(formatted.first?.startSeconds == 0 && formatted.last?.endSeconds == 3.0, "gom gap ngắn phải giữ span timing")
    }

    private static func testSpeechTimingRefiner() throws {
        let source = [segment(id: 1, start: 0, end: 3, text: "Xin chào các bạn")]
        let refined = SpeechTimingRefiner.refine(
            source,
            using: [SpeechActivityInterval(startSeconds: 0.5, endSeconds: 2.4, confidence: 0.9)]
        )
        try expect(refined.count == 1, "VAD không được tự tạo hoặc xóa cue")
        try expect(abs(refined[0].startSeconds - 0.42) < 0.02, "Mép đầu phải theo speech")
        try expect(abs(refined[0].endSeconds - 2.48) < 0.02, "Mép cuối phải theo speech")
        try expect(refined[0].text == source[0].text, "VAD không được sửa nội dung")
    }

    private static func testSpeechTimingFallback() throws {
        let source = [segment(id: 1, start: 1, end: 2.75, text: "Giữ timing cũ")]
        let refined = SpeechTimingRefiner.refine(source, using: [])
        try expect(refined.count == 1, "Fallback không được đổi số cue")
        try expect(refined[0].startSeconds == 1, "Fallback làm lệch mép đầu")
        try expect(refined[0].endSeconds == 2.75, "Fallback làm lệch mép cuối")
        try expect(refined[0].text == source[0].text, "Fallback làm đổi nội dung")
    }

    private static func testSpeechTimingSilenceGap() throws {
        let source = [
            segment(id: 1, start: 0, end: 2, text: "Câu một"),
            segment(id: 2, start: 2, end: 4.2, text: "Câu hai"),
        ]
        let refined = SpeechTimingRefiner.refine(
            source,
            using: [
                SpeechActivityInterval(startSeconds: 0.1, endSeconds: 1.4, confidence: 0.9),
                SpeechActivityInterval(startSeconds: 2.6, endSeconds: 3.8, confidence: 0.9),
            ]
        )
        try expect(refined[0].endSeconds < refined[1].startSeconds, "Khoảng lặng không được bị lấp kín")
        try expect(refined[0].endSeconds <= 1.5, "Cue đầu phải dừng sau lời nói")
        try expect(refined[1].startSeconds >= 2.5, "Cue sau phải bắt đầu gần lời nói")
    }

    private static func testWordTimestampGrouping() throws {
        let words = [
            word("Kính", 0.10, 0.35), word("thưa", 0.38, 0.62),
            word("quý", 0.65, 0.82), word("vị,", 0.85, 1.10),
            word("xin", 1.80, 2.00), word("chào.", 2.03, 2.35),
        ]
        let segments = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "vi")
        try expect(segments.count == 2, "pause 0,7 giây phải tạo hai cụm lời")
        try expect(segments[0].text == "Kính thưa quý vị,", "ghép cụm Việt sai")
        try expect(segments[0].endSeconds == 1.10, "mất mép cuối word của cụm đầu")
        try expect(segments[1].startSeconds == 1.80, "mất mép đầu word sau pause")
    }

    private static func testAdaptiveMultilingualPausePlanning() throws {
        let fastPhrase = [
            word("Nói", 0.00, 0.22), word("nhanh", 0.27, 0.50),
            word("nhưng", 0.84, 1.05), word("liền", 1.09, 1.30),
        ]
        let fastSegments = SpeechWordTimingProcessor.makeSegments(from: fastPhrase, languageCode: "vi")
        try expect(fastSegments.count == 1, "pause vừa 0,34 giây trong câu ngắn bị cắt cứng")

        let twoShortSentences = [
            word("Chào", 0.00, 0.30), word("bạn.", 0.34, 0.62),
            word("Cảm", 0.69, 0.96), word("ơn.", 1.00, 1.25),
        ]
        let shortSentenceSegments = SpeechWordTimingProcessor.makeSegments(from: twoShortSentences, languageCode: "vi")
        try expect(shortSentenceSegments.count == 1, "hai câu cực ngắn nói liền không được giữ chung để layout xét gộp")

        let twoReadableSentences = [
            word("Đây", 0.00, 0.35), word("là", 0.40, 0.70), word("câu", 0.75, 1.10),
            word("thứ", 1.15, 1.50), word("nhất.", 1.55, 2.35),
            word("Đây", 2.43, 2.78), word("là", 2.83, 3.13), word("câu", 3.18, 3.53),
            word("thứ", 3.58, 3.93), word("hai.", 3.98, 4.78),
        ]
        let readableSentenceSegments = SpeechWordTimingProcessor.makeSegments(from: twoReadableSentences, languageCode: "vi")
        try expect(readableSentenceSegments.count == 2, "hai câu đã đủ thời lượng bị gộp thành một cue dài")

        let hardSilence = [
            word("Câu", 0.00, 0.25), word("đầu", 0.28, 0.52),
            word("Câu", 1.30, 1.55), word("sau", 1.58, 1.82),
        ]
        let hardSegments = SpeechWordTimingProcessor.makeSegments(from: hardSilence, languageCode: "vi")
        try expect(hardSegments.count == 2, "pause mạnh 0,78 giây không tạo hard boundary")

        let automaticJapanese = [
            word("これは", 0.0, 0.3), word("短い", 0.34, 0.58),
            word("文です。", 0.62, 0.92), word("次です。", 1.02, 1.32),
        ]
        let japanese = SpeechWordTimingProcessor.makeSegments(from: automaticJapanese, languageCode: "auto")
        try expect(japanese.map(\.text).joined() == "これは短い文です。次です。", "Auto chèn khoảng trắng vào tiếng Nhật")

        let automaticChinese = [
            word("你好", 0.0, 0.3), word("，", 0.31, 0.34), word("世界", 0.38, 0.68), word("。", 0.69, 0.72),
        ]
        let chinese = SpeechWordTimingProcessor.makeSegments(from: automaticChinese, languageCode: "auto")
        try expect(chinese.map(\.text).joined() == "你好，世界。", "Auto chèn khoảng trắng vào tiếng Trung")

        let automaticThai = [
            word("สวัสดี", 0.0, 0.3), word("ครับ", 0.34, 0.58), word("ทุกคน", 0.62, 0.92),
        ]
        let thai = SpeechWordTimingProcessor.makeSegments(from: automaticThai, languageCode: "auto")
        try expect(thai.map(\.text).joined() == "สวัสดีครับทุกคน", "Auto chèn khoảng trắng vào tiếng Thái")

        let arabicTokens = ["هذا", "اختبار", "قصير", "للتوقيت", "هل", "يعمل", "اليوم؟", "نعم", "إنه", "يعمل", "بصورة", "جيدة", "مع", "الكلام", "المتواصل", "الآن"]
        let arabicWords = arabicTokens.enumerated().map { offset, token in
            word(token, Double(offset) * 0.5, Double(offset) * 0.5 + 0.42)
        }
        let arabic = SpeechWordTimingProcessor.makeSegments(from: arabicWords, languageCode: "ar")
        try expect(arabic.count >= 2, "Arabic dài không được chia dưới trần duration")
        try expect(arabic.first?.text.hasSuffix("؟") == true, "dấu hỏi Arabic không được ưu tiên làm boundary")

        let hindiTokens = ["यह", "एक", "लंबा", "वाक्य", "है।", "इसके", "बाद", "दूसरा", "वाक्य", "लगातार", "बोला", "गया", "है", "और", "अब", "समाप्त"]
        let hindiWords = hindiTokens.enumerated().map { offset, token in
            word(token, Double(offset) * 0.5, Double(offset) * 0.5 + 0.42)
        }
        let hindi = SpeechWordTimingProcessor.makeSegments(from: hindiWords, languageCode: "hi")
        try expect(hindi.count >= 2, "Hindi dài không được chia dưới trần duration")
        try expect(hindi.first?.text.hasSuffix("।") == true, "dấu danda Hindi không được ưu tiên làm boundary")
    }

    private static func testCachedWaveformSilencePlanning() throws {
        let words = [
            word("Xin", 0.00, 0.24),
            word("chào", 0.70, 0.98),
        ]
        let withoutAudio = SpeechWordTimingProcessor.makeSegments(
            from: words,
            languageCode: "vi"
        )
        let evidence = SpeechBoundaryAudioEvidence(
            silenceScores: Array(repeating: 1, count: 100),
            duration: 2
        )
        let withAudio = SpeechWordTimingProcessor.makeSegments(
            from: words,
            languageCode: "vi",
            audioEvidence: evidence
        )
        try expect(withoutAudio.count == 1, "pause mềm không có audio bị cắt cứng")
        try expect(withAudio.count == 2, "pause mềm có đáy năng lượng rõ chưa được nâng thành boundary")

        let shortGapWords = [word("Nói", 0.00, 0.24), word("liền", 0.40, 0.68)]
        let shortGap = SpeechWordTimingProcessor.makeSegments(
            from: shortGapWords,
            languageCode: "vi",
            audioEvidence: evidence
        )
        try expect(shortGap.count == 1, "waveform không được cắt micro-pause dưới 0,20 giây")
    }

    private static func testSafeAdjacentCueMerging() throws {
        var oneLine = SubtitleWrapStyle.appDefault
        oneLine.maxLines = 1
        oneLine.maxCharsPerLine = 33
        let short = [
            segment(id: 1, start: 0.0, end: 0.9, text: "Xin chào."),
            segment(id: 2, start: 0.95, end: 1.8, text: "Cảm ơn bạn."),
        ]
        let merged = SubtitleTranscriptPostProcessor.format(
            short,
            sourceLanguage: "vi",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(merged.count == 1, "hai cue ngắn nói liền và vừa khung chưa được gộp")
        try expect(SubtitleWrapStyle.flattenToOneLine(merged[0].text) == "Xin chào. Cảm ơn bạn.", "gộp cue làm đổi text")
        try expect(merged[0].startSeconds == 0 && merged[0].endSeconds == 1.8, "gộp cue làm mất span timing")

        let separated = [
            segment(id: 1, start: 0.0, end: 0.9, text: "Xin chào."),
            segment(id: 2, start: 1.75, end: 2.6, text: "Cảm ơn bạn."),
        ]
        let kept = SubtitleTranscriptPostProcessor.format(
            separated,
            sourceLanguage: "vi",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(kept.count == 2, "cue bị gộp xuyên qua khoảng lặng mạnh")

        let japaneseShort = [
            segment(id: 1, start: 0.0, end: 0.8, text: "ありがとう。"),
            segment(id: 2, start: 0.86, end: 1.6, text: "またね。"),
        ]
        let japaneseMerged = SubtitleTranscriptPostProcessor.format(
            japaneseShort,
            sourceLanguage: "ja",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_000,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(japaneseMerged.count == 1, "hai cue Nhật ngắn nói liền chưa được gộp an toàn")
        try expect(japaneseMerged[0].text == "ありがとう。またね。", "gộp cue Nhật chèn khoảng trắng hoặc đổi Kinsoku")

        let dialogue = [
            segment(id: 1, start: 0.0, end: 0.8, text: "Tôi đồng ý."),
            segment(id: 2, start: 0.84, end: 1.6, text: "— Tôi thì không."),
        ]
        let dialogueResult = SubtitleTranscriptPostProcessor.format(
            dialogue,
            sourceLanguage: "vi",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(dialogueResult.count == 2, "gộp cue xuyên qua dấu hiệu đổi người nói")

        let koreanChunks = [
            segment(id: 1, start: 0.0, end: 0.9, text: "안녕하세요"),
            segment(id: 2, start: 1.0, end: 1.8, text: "여러분 반갑습니다"),
        ]
        let korean = SubtitleTranscriptPostProcessor.format(
            koreanChunks,
            sourceLanguage: "ko",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: true
        )
        try expect(korean.map(\.text).joined(separator: " ").contains("안녕하세요 여러분"), "gom chunk Hàn làm dính hai eojeol")

        let secondPass = SubtitleTranscriptPostProcessor.format(
            merged,
            sourceLanguage: "vi",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(secondPass.map(\.text) == merged.map(\.text), "optimizer gộp cue không idempotent")
        try expect(secondPass.map(\.timing) == merged.map(\.timing), "optimizer chạy lại làm đổi timing")
    }

    private static func testRequiredWordPauseSurvivesLayout() throws {
        var oneLine = SubtitleWrapStyle.appDefault
        oneLine.maxLines = 1
        let planned = [
            segment(id: 1, start: 0.00, end: 0.70, text: "Xin chào."),
            segment(id: 2, start: 1.25, end: 1.95, text: "Cảm ơn."),
        ]
        let formatted = SubtitleTranscriptPostProcessor.format(
            planned,
            sourceLanguage: "vi",
            style: oneLine,
            fontSize: 54,
            fontName: "Helvetica",
            containerWidth: 1_400,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(formatted.count == 2, "layout gộp ngược cue qua pause 0,55 giây")
        try expect(abs(formatted[0].endSeconds - 0.70) < 0.001, "layout làm mất mép pause bắt buộc")
        try expect(abs(formatted[1].startSeconds - 1.25) < 0.001, "layout làm mất đầu cue sau pause")
    }

    private static func testWordTimestampContinuousSpeechPlanning() throws {
        let tokens = (1...42).map { "từ\($0)" }
        let words = tokens.enumerated().map { offset, token in
            let start = Double(offset) * 0.34
            return word(token, start, start + 0.29)
        }
        let segments = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "vi")
        try expect(segments.count >= 3, "lời nói liên tục của Large V3 vẫn bị giữ thành cue dài")
        try expect(
            segments.allSatisfy { $0.endSeconds - $0.startSeconds <= 6.01 },
            "cue word timing vượt trần sáu giây"
        )
        try expect(
            segments.allSatisfy { $0.endSeconds - $0.startSeconds >= 2.0 },
            "planner tạo cue đuôi quá ngắn trong lời nói liên tục"
        )
        let rebuilt = segments.map(\.text).joined(separator: " ")
        try expect(rebuilt == tokens.joined(separator: " "), "planner làm mất hoặc đảo word")
    }

    private static func testWordTimestampBoundariesSurviveLayout() throws {
        let planned = [
            segment(id: 1, start: 0, end: 4.4, text: "Đây là cụm lời đầu tiên được lập theo nhịp đọc"),
            segment(id: 2, start: 4.4, end: 8.8, text: "và đây là cụm tiếp theo không được nối ngược lại"),
        ]
        let formatted = SubtitleTranscriptPostProcessor.format(
            planned,
            sourceLanguage: "vi",
            style: SubtitleWrapStyle(maxCharsPerLine: 33),
            fontSize: 54,
            maximumSpeechGap: 0.45,
            coalescesSpeechChunks: false
        )
        try expect(formatted.count >= 2, "layout đã ghép ngược boundary word timing")
        try expect(
            formatted.contains { abs($0.endSeconds - 4.4) < 0.001 },
            "mất mép timing đã lập giữa hai cụm"
        )
    }

    private static func testWordTimestampRetime() throws {
        let words = [
            word("Kính", 0.10, 0.35), word("thưa", 0.38, 0.62),
            word("quý", 0.65, 0.82), word("vị,", 0.85, 1.10),
            word("xin", 1.80, 2.00), word("chào.", 2.03, 2.35),
        ]
        let laidOut = [
            segment(id: 1, start: 0, end: 2.5, text: "Kính thưa quý vị,"),
            segment(id: 2, start: 2.5, end: 5, text: "xin chào."),
        ]
        let retimed = SpeechWordTimingProcessor.retime(laidOut, using: words)
        try expect(retimed[0].startSeconds == 0.10, "cue đầu không bám word đầu")
        try expect(retimed[0].endSeconds == 1.10, "cue đầu không bám word cuối")
        try expect(retimed[1].startSeconds == 1.80, "cue sau không giữ khoảng lặng")
        try expect(retimed[1].endSeconds == 2.35, "cue sau không bám word cuối")
    }

    private static func testWordTimestampRetimeRejectsReorderedText() throws {
        let source = [segment(id: 1, start: 4, end: 7, text: "sau trước")]
        let words = [word("trước", 0.1, 0.4), word("sau", 0.5, 0.8)]
        let result = SpeechWordTimingProcessor.retime(source, using: words)
        try expect(result[0].startSeconds == 4 && result[0].endSeconds == 7, "retime chỉ so độ dài nên nhận nhầm text đảo thứ tự")
    }

    private static func testWordTimestampFallback() throws {
        let source = [segment(id: 1, start: 4, end: 7, text: "Nội dung đầy đủ")]
        let mismatched = [word("khác", 0.1, 0.4)]
        let result = SpeechWordTimingProcessor.retime(source, using: mismatched)
        try expect(result[0].startSeconds == 4 && result[0].endSeconds == 7, "mismatch không fallback timing")
        try expect(
            !SpeechWordTimingProcessor.hasMatchingTranscript(words: mismatched, transcript: "Nội dung đầy đủ"),
            "mismatch provider phải bị phát hiện"
        )
    }

    private static func testWordTimestampCJK() throws {
        let words = [
            word("你好", 0.1, 0.4), word("，", 0.4, 0.45),
            word("世界", 0.5, 0.8), word("。", 0.8, 0.85),
        ]
        let segments = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "zh")
        try expect(segments.count == 1, "dấu câu CJK không được tạo cue riêng")
        try expect(segments[0].text == "你好，世界。", "CJK bị chèn khoảng trắng")
        try expect(
            SpeechWordTimingProcessor.hasMatchingTranscript(words: words, transcript: "你好，世界。"),
            "CJK word list phải khớp transcript"
        )
    }

    private static func testBoundedSubtitleEditHistory() async throws {
        try await MainActor.run {
            let history = SubtitleEditHistory()
            let seed = SRTSegment(
                id: 1,
                index: 1,
                timing: SRTTimecode.makeTiming(start: 0, end: 1),
                startSeconds: 0,
                endSeconds: 1,
                text: "revision 0"
            )
            var current = [seed]
            let totalEdits = SubtitleEditHistory.maximumSnapshots + 10

            for revision in 1...totalEdits {
                history.record(before: current)
                current = [SRTSegmentEditor.withText(seed, text: "revision \(revision)")]
            }

            var undoCount = 0
            while let restored = history.undo(current: current) {
                current = restored
                undoCount += 1
            }
            try expect(undoCount == SubtitleEditHistory.maximumSnapshots, "history phải giữ đúng số bước tối đa")
            try expect(current.first?.text == "revision 10", "khi vượt giới hạn phải bỏ bước cũ nhất")
            try expect(history.canRedo, "undo phải tạo redo")

            var redoCount = 0
            while let restored = history.redo(current: current) {
                current = restored
                redoCount += 1
            }
            try expect(redoCount == SubtitleEditHistory.maximumSnapshots, "redo phải trả lại đủ các bước còn giữ")
            try expect(current.first?.text == "revision \(totalEdits)", "redo không trả sai trạng thái cuối")

            history.record(before: current)
            current = [SRTSegmentEditor.withText(seed, text: "revision new")]
            try expect(!history.canRedo, "edit mới phải xoá nhánh redo cũ")
        }
    }

    private static func testWaveformPeakService() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-waveform-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try require(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 2),
            "không tạo được format WAV test"
        )
        // Đóng writer trước khi AVAssetReader mở lại file; WAV chỉ ghi header cuối
        // khi AVAudioFile được giải phóng.
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let frameCount: AVAudioFrameCount = 8_000
            let buffer = try require(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                "không tạo được buffer WAV test"
            )
            buffer.frameLength = frameCount
            guard let channels = buffer.floatChannelData else {
                throw TestFailure(description: "WAV test không có float channel data")
            }
            for frame in 0..<Int(frameCount) {
                let sample: Float = frame.isMultiple(of: 240) ? 0.9 : 0.08
                channels[0][frame] = sample
                channels[1][frame] = -sample
            }
            try file.write(from: buffer)
        }

        let result = try await WaveformPeakService.loadPeaks(url: url, targetBins: 240)
        try expect(abs(result.duration - 1) < 0.03, "waveform stereo phải giữ duration 1 giây")
        try expect(result.peaks.count >= 240, "waveform phải tạo đủ peak")
        try expect((result.peaks.max() ?? 0) > 0.8, "waveform phải giữ peak audio")
    }

    private static func testPunctuationSafeWrap() throws {
        let style = SubtitleWrapStyle(maxCharsPerLine: 20)
        let punctuation = SubtitleWrapStyle.wrapText(
            "This sentence has a comma, followed by short words.",
            style: style,
            cjk: false
        )
        try expect(
            punctuation.contains("comma,\nfollowed"),
            "dấu câu hợp lý phải được ưu tiên khi đổi chữ/dòng"
        )

        let groupedNumber = SubtitleWrapStyle.wrapText(
            "Sản lượng đạt 100.000 tỷ trong năm nay, theo báo cáo mới.",
            style: SubtitleWrapStyle(maxCharsPerLine: 26),
            cjk: false
        )
        try expect(!groupedNumber.contains("100.\n000"), "không được ngắt bên trong số phân nhóm 100.000")

        let longCue = SubtitleWrapStyle.wrapText(
            "Readable subtitles should never split a Latin word in the middle.",
            style: SubtitleWrapStyle(maxCharsPerLine: 18),
            cjk: false
        )
        try expect(!longCue.contains("subtitl\nes"), "không được chém giữa từ Latin")
        try expect(!longCue.contains("midd\nle"), "fallback không được chém giữa từ Latin")
    }

    private static func testNativeSubtitleLayout() throws {
        let narrow = SubtitleLayoutEngine.measuredWidth(of: "iiiiiiiiii", fontName: "Helvetica", fontSize: 54)
        let wide = SubtitleLayoutEngine.measuredWidth(of: "WWWWWWWWWW", fontName: "Helvetica", fontSize: 54)
        try expect(wide > narrow * 2, "engine vẫn đang coi mọi ký tự có cùng độ rộng")

        let oneLineConfig = SubtitleLayoutConfiguration(
            languageCode: "vi",
            fontName: "Helvetica",
            fontSize: 54,
            containerWidth: 720,
            maxLines: 1,
            preferredCharactersPerLine: 33,
            explicitBreakPolicy: .automatic
        )
        let source = "Đây là một câu phụ đề tương đối dài cần được chia thành nhiều cue một dòng nhưng tuyệt đối không được làm mất chữ."
        let oneLine = SubtitleLayoutEngine.layoutPieces(source, configuration: oneLineConfig)
        try expect(oneLine.count > 1, "một dòng quá dài phải tách thành nhiều cue")
        try expect(oneLine.allSatisfy { $0.lines.count == 1 && !$0.text.contains("\n") }, "mode một dòng sinh newline")
        try expect(oneLine.allSatisfy { ($0.lineWidths.max() ?? 0) <= oneLineConfig.containerWidth + 0.5 }, "một dòng tràn container thật")
        let rebuilt = oneLine.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        try expect(rebuilt == source, "layout một dòng làm mất hoặc đảo chữ")

        var twoLineConfig = oneLineConfig
        twoLineConfig.maxLines = 2
        twoLineConfig.containerWidth = 760
        let twoLine = SubtitleLayoutEngine.layoutPieces(source, configuration: twoLineConfig)
        try expect(twoLine.allSatisfy { $0.lines.count <= 2 }, "mode hai dòng sinh dòng thứ ba")
        try expect(twoLine.allSatisfy { ($0.lineWidths.max() ?? 0) <= twoLineConfig.containerWidth + 0.5 }, "hai dòng tràn container thật")
        let secondPass = twoLine.flatMap { SubtitleLayoutEngine.layoutPieces($0.text, configuration: twoLineConfig) }
        try expect(secondPass.map(\.text) == twoLine.map(\.text), "layout chạy lần hai làm thay đổi kết quả")

        let number = SubtitleLayoutEngine.layoutPieces(
            "Doanh thu đạt 100.000 tỷ đồng, tăng mạnh trong năm nay.",
            configuration: twoLineConfig
        )
        try expect(!number.contains { $0.text.contains("100.\n000") }, "layout native chẻ cụm số")
    }

    private static func testNativeSubtitleLayoutLanguages() throws {
        let manualConfig = SubtitleLayoutConfiguration(
            languageCode: "vi",
            fontName: "Helvetica",
            fontSize: 48,
            containerWidth: 900,
            maxLines: 2,
            preferredCharactersPerLine: 33,
            explicitBreakPolicy: .preserve
        )
        let manual = SubtitleLayoutEngine.layoutPieces("Dòng trên có chủ ý\nDòng dưới do người dùng đặt", configuration: manualConfig)
        try expect(manual.count == 1 && manual[0].text == "Dòng trên có chủ ý\nDòng dưới do người dùng đặt", "manual newline bị engine viết lại")

        let samples: [(String, String)] = [
            ("ja", "これは読みやすい日本語字幕です。必要なら自然な位置で分割します。"),
            ("zh", "这是一段用于测试自动换行和字幕宽度的中文文本。"),
            ("ko", "이 문장은 한국어 자막 줄바꿈을 안전하게 검사하기 위한 예시입니다."),
            ("th", "นี่คือข้อความคำบรรยายภาษาไทยสำหรับทดสอบการตัดบรรทัดอย่างปลอดภัย"),
            ("hi", "यह उपशीर्षक पंक्ति विभाजन का परीक्षण करने के लिए एक उदाहरण है।"),
            ("ar", "هذا مثال لاختبار تقسيم سطر الترجمة بطريقة آمنة وواضحة."),
            ("vi", "Gia đình 👨‍👩‍👧‍👦 cùng xem video và đọc phụ đề rõ ràng."),
        ]
        for (language, sample) in samples {
            var config = manualConfig
            config.languageCode = language
            config.containerWidth = 620
            config.explicitBreakPolicy = .automatic
            let pieces = SubtitleLayoutEngine.layoutPieces(sample, configuration: config)
            let rebuilt = pieces.map { $0.lines.joined() }.joined()
                .replacingOccurrences(of: " ", with: "")
            try expect(rebuilt == sample.replacingOccurrences(of: " ", with: ""), "layout \(language) làm mất grapheme/nội dung")
            try expect(pieces.allSatisfy { $0.lines.count <= 2 }, "layout \(language) vượt hai dòng")
            try expect(!pieces.contains { $0.text.contains("👨\n‍") }, "layout chẻ emoji ZWJ")
        }
    }

    private static func testMultilingualSingleLineBreakScoring() throws {
        func pieces(_ text: String, language: String, width: Double) -> [String] {
            SubtitleLayoutEngine.layoutPieces(
                text,
                configuration: SubtitleLayoutConfiguration(
                    languageCode: language,
                    fontName: "Helvetica",
                    fontSize: 48,
                    containerWidth: width,
                    maxLines: 1,
                    preferredCharactersPerLine: 33,
                    explicitBreakPolicy: .automatic
                )
            ).map(\.text)
        }

        let vietnamese = pieces(
            "Những pha cất cánh từ tàu sân bay đầy ấn tượng với khả năng tác chiến hiện đại và vượt trội.",
            language: "vi",
            width: 760
        )
        try expect(vietnamese.count > 1, "mẫu Việt chưa đủ hẹp để kiểm tra ngắt cue")
        let vietnameseCuts = zip(vietnamese, vietnamese.dropFirst()).map { left, right in
            let lhs = left.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            let rhs = right.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            return lhs.lowercased() + " " + rhs.lowercased()
        }
        let forbiddenVietnameseCuts: Set<String> = [
            "tàu sân", "đầy ấn", "ấn tượng", "khả năng", "tác chiến", "hiện đại", "vượt trội",
        ]
        try expect(
            Set(vietnameseCuts).isDisjoint(with: forbiddenVietnameseCuts),
            "mode một dòng Việt vẫn cắt giữa cụm nhiều âm tiết: \(vietnameseCuts)"
        )
        try expect(
            vietnamese.last.map { $0.count >= 12 } ?? false,
            "mode một dòng Việt vẫn để cue cuối quá cụt"
        )

        let autoVietnamese = pieces(
            "Sức mạnh hủy diệt của F-18 Hornet và Super Hornet, niềm tự hào không quân Hoa Kỳ. Bạn đã bao giờ tự hỏi vì sao F-18 Hornet lại hiện đại và có khả năng tác chiến vượt trội?",
            language: "auto",
            width: 760
        )
        let autoCuts = zip(autoVietnamese, autoVietnamese.dropFirst()).map { left, right in
            let lhs = left.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            let rhs = right.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            return lhs.lowercased() + " " + rhs.lowercased()
        }
        let forbiddenAutoCuts: Set<String> = [
            "sức mạnh", "hủy diệt", "tự hào", "không quân", "hiện đại", "khả năng",
            "tác chiến", "vượt trội",
        ]
        try expect(Set(autoCuts).isDisjoint(with: forbiddenAutoCuts), "Auto không kích hoạt tailoring Việt: \(autoCuts)")
        try expect(!autoVietnamese.contains { $0.hasSuffix(" F") }, "Auto vẫn chẻ model ở F|-18")
        try expect(!autoVietnamese.contains { $0.hasPrefix("-18") }, "Auto vẫn tạo cue bắt đầu bằng -18")
        try expect(autoVietnamese.joined(separator: " ").contains("F-18 Hornet"), "Auto làm hỏng token F-18 Hornet")

        let english = pieces(
            "The F-18 Super Hornet remains one of the most capable aircraft in the world today.",
            language: "en",
            width: 680
        )
        try expect(!zip(english, english.dropFirst()).contains { left, right in
            left.hasSuffix("F-18") && right.hasPrefix("Super")
        }, "mode Anh cắt tên model F-18 Super Hornet")
        try expect(!english.dropLast().contains { $0.split(separator: " ").last.map { ["a", "an", "the", "to", "of", "in"].contains($0.lowercased()) } ?? false }, "mode Anh để mạo từ/giới từ ở cuối cue")

        let russian = pieces(
            "Этот самолёт создан для выполнения сложных задач и защиты воздушного пространства.",
            language: "ru",
            width: 690
        )
        let russianOrphans: Set<String> = ["а", "в", "во", "для", "до", "за", "и", "из", "или", "к", "на", "но", "о", "от", "по", "с", "у"]
        try expect(!russian.dropLast().contains { cue in
            cue.split(separator: " ").last.map { russianOrphans.contains($0.lowercased()) } ?? false
        }, "mode Nga để giới từ/liên từ ở cuối cue")

        for (language, sample) in [
            ("zh", "这是一段用于测试单行字幕自然分段和标点位置的中文文本。"),
            ("ko", "이 문장은 한 줄 자막이 너무 짧게 남지 않도록 검사하는 예시입니다."),
            ("th", "นี่คือข้อความสำหรับตรวจสอบการแบ่งคำบรรยายหนึ่งบรรทัดให้เป็นธรรมชาติ"),
        ] {
            let result = pieces(sample, language: language, width: 470)
            try expect(!result.isEmpty, "mode \(language) không sinh được cue")
            try expect(result.allSatisfy { !$0.isEmpty && !$0.contains("\n") }, "mode \(language) sinh cue rỗng/newline")
            try expect(result.joined().replacingOccurrences(of: " ", with: "") == sample.replacingOccurrences(of: " ", with: ""), "mode \(language) làm mất nội dung")
        }

        // Nhật là đường đã chốt: chỉ khóa nội dung/Kinsoku, không đi qua optimizer mới.
        let japanese = pieces("これは日本語の字幕です。自然な位置で安全に分割します。", language: "ja", width: 470)
        try expect(japanese.joined() == "これは日本語の字幕です。自然な位置で安全に分割します。", "hồi quy làm đổi nội dung tiếng Nhật")
    }

    private static func testMultilingualTwoLineBreakScoring() throws {
        func pieces(_ text: String, language: String, width: Double) -> [SubtitleLayoutResult] {
            SubtitleLayoutEngine.layoutPieces(
                text,
                configuration: SubtitleLayoutConfiguration(
                    languageCode: language,
                    fontName: "Helvetica",
                    fontSize: 46,
                    containerWidth: width,
                    maxLines: 2,
                    preferredCharactersPerLine: 28,
                    topLineRatio: 1,
                    explicitBreakPolicy: .automatic
                )
            )
        }

        let vietnameseSource = "Những gia đình trẻ đang chia sẻ thông tin và công việc để chuẩn bị cho cuộc sống ngày mai."
        let vietnamese = pieces(vietnameseSource, language: "vi", width: 520)
        try expect(vietnamese.count > 1, "mẫu Việt hai dòng chưa kích hoạt optimizer cue")
        try expect(vietnamese.allSatisfy { $0.lines.count <= 2 && $0.fits }, "hai dòng Việt vượt layout")
        let vietnameseBoundaries = zip(vietnamese, vietnamese.dropFirst()).map {
            let left = $0.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last.map(String.init) ?? ""
            let right = $1.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first.map(String.init) ?? ""
            return left.lowercased() + " " + right.lowercased()
        }
        let protectedVietnamese: Set<String> = ["gia đình", "thông tin", "công việc", "cuộc sống", "ngày mai"]
        try expect(Set(vietnameseBoundaries).isDisjoint(with: protectedVietnamese), "hai dòng Việt cắt cụm bảo vệ: \(vietnameseBoundaries)")

        let englishSource = "The project will continue with the new subtitle planner because the current result needs better line treatment."
        let english = pieces(englishSource, language: "en", width: 500)
        let badEnglishEnds: Set<String> = ["the", "a", "an", "will", "with", "because"]
        try expect(!english.dropLast().contains { cue in
            cue.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last.map {
                badEnglishEnds.contains($0.trimmingCharacters(in: .punctuationCharacters).lowercased())
            } ?? false
        }, "hai dòng Anh để từ chức năng ở cuối cue")

        let chineseWords = [
            word("中华人民共和国", 0.0, 1.0),
            word("欢迎", 1.05, 1.40),
            word("大家", 1.45, 1.80),
        ]
        let chineseText = "中华人民共和国欢迎大家"
        let offsets = SpeechWordTimingProcessor.verifiedCueBreakOffsets(
            in: chineseText,
            using: chineseWords,
            languageCode: "zh"
        )
        let chinese = SubtitleLayoutEngine.layoutPieces(
            chineseText,
            configuration: SubtitleLayoutConfiguration(
                languageCode: "zh",
                fontName: "PingFang SC",
                fontSize: 48,
                containerWidth: 360,
                maxLines: 1,
                preferredCharactersPerLine: 12,
                explicitBreakPolicy: .automatic
            ),
            allowedCueBreakOffsets: offsets
        )
        try expect(chinese.first?.text == "中华人民共和国", "cue Trung cắt giữa token timestamp nhiều chữ")

        let koreanSource = "이 프로젝트는 자연스러운 한국어 자막 줄바꿈을 위해 전체 문장을 함께 검사합니다."
        let korean = pieces(koreanSource, language: "ko", width: 460)
        try expect(korean.allSatisfy { result in
            result.lines.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") }
        }, "hai dòng Hàn cắt sai ranh giới eojeol")
    }

    private static func unpunctuatedConfiguration(_ language: String, lines: Int) -> SubtitleLayoutConfiguration {
        SubtitleLayoutConfiguration(languageCode: language, fontName: "Helvetica", fontSize: 38,
            containerWidth: 620, maxLines: lines, preferredCharactersPerLine: 40, topLineRatio: 1)
    }

    private static func testUnpunctuatedMultilingualLayout() throws {
        let coreSamples = [
            ("vi", "Trời mưa rất lớn nên chúng tôi quyết định ở lại nhà", "nên"),
            ("en", "The rain was very heavy so we decided to stay at home", "so"),
            ("ko", "비가 많이 와서 우리는 집에 머물기로 했습니다 하지만 내일은 밖으로 나갈 수 있습니다", "하지만"),
            ("zh", "今天下雨很大所以我们决定留在家里但是明天还可以出去玩", "所以"),
            ("zh-Hant", "今天下雨很大所以我們決定留在家裡但是明天還可以出去玩", "所以"),
            ("fr", "La pluie était très forte mais nous avons décidé de rester à la maison", "mais"),
            ("de", "Heute regnet es sehr stark deshalb bleiben wir lieber zu Hause", "deshalb"),
            ("ru", "Сегодня идёт сильный дождь поэтому мы решили остаться дома", "поэтому"),
            ("th", "วันนี้ฝนตกหนักมากดังนั้นเราจึงตัดสินใจอยู่ที่บ้าน", "ดังนั้น"),
        ]
        for (language, sample, connector) in coreSamples {
            for lines in [1, 2] {
                let pieces = SubtitleLayoutEngine.layoutPieces(sample,
                    configuration: unpunctuatedConfiguration(language, lines: lines))
                try expect(pieces.allSatisfy { $0.fits && $0.lines.count <= lines }, "layout không dấu vượt khung: \(language)")
                try expect(pieces.map(\.text).joined().filter { !$0.isWhitespace }
                    == sample.filter { !$0.isWhitespace }, "layout không dấu mất/sửa chữ: \(language)")
                let displayed = pieces.flatMap(\.lines)
                try expect(!displayed.dropLast().contains { $0.hasSuffix(connector) }, "từ nối bị bỏ cuối dòng/cue: \(language)")
                if language == "ko" {
                    try expect(!displayed.dropLast().contains { $0.hasSuffix("우리는") || $0.hasSuffix("집에") || $0.hasSuffix(" 수") }, "Hàn tách chủ ngữ/trợ từ khỏi cụm")
                }
            }
        }
        let additionalSamples = [
            ("es", "Hoy llueve muy fuerte pero decidimos quedarnos en casa porque necesitamos descansar"),
            ("pt", "Hoje chove muito mas decidimos ficar em casa porque precisamos descansar"),
            ("it", "Oggi piove molto ma abbiamo deciso di restare a casa perché dobbiamo riposare"),
            ("uk", "Сьогодні дуже сильний дощ але ми вирішили залишитися вдома"),
            ("id", "Hari ini hujan sangat deras tetapi kami memutuskan untuk tetap di rumah"),
            ("ms", "Hari ini hujan sangat lebat tetapi kami memilih untuk tinggal di rumah"),
            ("tr", "Bugün çok yağmur yağıyor ama evde kalmaya karar verdik çünkü dinlenmek istiyoruz"),
            ("nl", "Vandaag regent het heel hard maar we hebben besloten om thuis te blijven"),
            ("pl", "Dzisiaj pada bardzo mocny deszcz ale postanowiliśmy zostać w domu"),
            ("ar", "المطر غزير اليوم لكننا قررنا البقاء في المنزل لأننا نحتاج إلى الراحة"),
            ("hi", "आज बहुत बारिश हो रही है लेकिन हमने घर पर रहने का फैसला किया क्योंकि हमें आराम चाहिए"),
            ("sv", "Det regnar mycket idag men vi bestämde oss för att stanna hemma"),
            ("da", "Det regner meget i dag men vi besluttede at blive hjemme"),
            ("no", "Det regner veldig mye i dag men vi bestemte oss for å bli hjemme"),
            ("fi", "Tänään sataa paljon mutta päätimme jäädä kotiin koska haluamme levätä"),
            ("el", "Σήμερα βρέχει πολύ αλλά αποφασίσαμε να μείνουμε στο σπίτι"),
            ("bn", "আজ অনেক বৃষ্টি হচ্ছে তাই আমরা বাড়িতে থাকার সিদ্ধান্ত নিয়েছি"),
            ("he", "היום יורד גשם חזק אבל החלטנו להישאר בבית"),
        ]
        for (language, sample) in additionalSamples {
            for lines in [1, 2] {
                let pieces = SubtitleLayoutEngine.layoutPieces(sample,
                    configuration: unpunctuatedConfiguration(language, lines: lines))
                try expect(pieces.allSatisfy { $0.fits && $0.lines.count <= lines }, "fallback ngôn ngữ vượt khung: \(language)")
                try expect(pieces.map(\.text).joined().filter { !$0.isWhitespace }
                    == sample.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }, "fallback ngôn ngữ đổi chữ: \(language)")
            }
        }
        let manual = "Đây là dòng do người dùng đặt\nvà đây là dòng thứ hai"
        var config = unpunctuatedConfiguration("vi", lines: 2)
        config.explicitBreakPolicy = .preserve
        try expect(SubtitleLayoutEngine.layoutPieces(manual, configuration: config).first?.text == manual,
                   "ngữ cảnh ghi đè Enter có chủ ý")
    }

    private static func testUnpunctuatedWordPlanning() throws {
        let text = "The rain was very heavy so we decided to stay at home"
        let tokens = text.split(separator: " ").map(String.init)
        let words = tokens.enumerated().map { index, token in
            word(token, Double(index) * 0.72, Double(index) * 0.72 + 0.65)
        }
        let planned = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "en")
        try expect(planned.map(\.text) == ["The rain was very heavy", "so we decided to stay at home"],
                   "word không dấu vẫn chia sau từ nối hoặc mất mệnh đề: \(planned.map(\.text))")
        try expect(planned.allSatisfy { $0.durationSeconds <= 6.001 }, "ngữ cảnh vượt trần timing")

        let pauseWords = [word("alpha", 0, 0.3), word("beta", 0.35, 0.65),
                          word("gamma", 1.1, 1.4), word("delta", 1.45, 1.75)]
        let pauseText = "alpha beta gamma delta"
        let costs = SpeechWordTimingProcessor.verifiedCueBoundaryCosts(in: pauseText, using: pauseWords, languageCode: "en")
        try expect(costs[10] == -18 && costs.count == 1, "pause thiếu dấu không tới boundary đúng")
        try expect(SpeechWordTimingProcessor.verifiedCueBoundaryCosts(in: "beta alpha gamma delta",
            using: pauseWords, languageCode: "en").isEmpty, "word mismatch vẫn dùng audio evidence")
        let jaWords = [word("字幕", 0, 0.3), word("表示", 1.1, 1.4)]
        try expect(SpeechWordTimingProcessor.verifiedCueBoundaryCosts(in: "字幕表示", using: jaWords,
            languageCode: "ja").isEmpty, "pause mới làm đổi nhánh Nhật")
    }

    private static func testJapaneseLayoutGolden() throws {
        let samples: [(String, Int, [String])] = [
            ("これは日本語の字幕です。自然な位置で安全に分割します。", 1,
             ["これは日本語の字幕です。", "自然な位置で安全に分割します。"]),
            ("これは日本語の字幕です。自然な位置で安全に分割します。", 2,
             ["これは日本語の字幕です。\n自然な位置で安全に分割します。"]),
            ("最新のF-18機について説明します。「安全な字幕」を表示してください。", 1,
             ["最新のF-18機について説明します。", "「安全な字幕」を表示してくださ", "い。"]),
            ("最新のF-18機について説明します。「安全な字幕」を表示してください。", 2,
             ["最新のF-18機について説明します。", "「安全な字\n幕」を表示してください。"]),
        ]
        for (text, lines, expected) in samples {
            try expect(SubtitleLayoutEngine.layoutPieces(text,
                configuration: unpunctuatedConfiguration("ja", lines: lines)).map(\.text) == expected,
                "Nhật đổi exact golden trước sửa")
        }
    }

    private static func testVerifiedTokenEmergencyBoundary() throws {
        let text = "中华人民共和国欢迎"
        var config = unpunctuatedConfiguration("zh", lines: 1)
        config.fontSize = 48; config.containerWidth = 180
        let pieces = SubtitleLayoutEngine.layoutPieces(text, configuration: config, allowedCueBreakOffsets: [7])
        try expect(pieces.map(\.text) == ["中华人民共和国", "欢迎"], "fallback chẻ token provider quá rộng")
        try expect(!pieces[0].fits, "token quá rộng phải báo overflow thay vì chẻ chữ âm thầm")
    }

    private static func testLongTranscriptReflow() throws {
        let samples = [
            ("vi", "Những gia đình trẻ đang chia sẻ thông tin và công việc để chuẩn bị cho cuộc sống ngày mai."),
            ("en", "The project will continue with the new subtitle planner because the current result needs better line treatment."),
            ("ko", "이 프로젝트는 자연스러운 한국어 자막 줄바꿈을 위해 전체 문장을 함께 검사합니다."),
            ("zh", "这是一段用于测试字幕自然分段和标点位置的中文文本，我们希望所有文字都能清楚地显示在画面中。"),
        ]
        func content(_ cues: [SRTSegment]) -> String {
            cues.map(\.text).joined().filter { !$0.isWhitespace }
        }
        for (language, sample) in samples {
            var cues: [SRTSegment] = []
            for i in 0..<180 {
                let start = Double(i) * 3
                let end = start + 2.9
                cues.append(SRTSegment(id: i + 1, index: i + 1,
                    timing: SRTTimecode.makeTiming(start: start, end: end),
                    startSeconds: start, endSeconds: end, text: sample + " \(i)."))
            }
            for lines in [1, 2] {
                var style = SubtitleWrapStyle()
                style.maxLines = lines
                let start = Date()
                let output = SubtitleTranscriptPostProcessor.format(cues,
                    sourceLanguage: language, style: style, fontSize: 54,
                    fontName: "Helvetica", containerWidth: 900)
                let elapsed = Date().timeIntervalSince(start)
                print("  reflow \(language) \(lines) dòng: \(String(format: "%.2f", elapsed))s / 9 phút")
                try expect(content(output) == content(cues), "reflow \(language) mất/sai thứ tự chữ")
                try expect(output.allSatisfy { cue in
                    cue.startSeconds >= 0 && cue.endSeconds <= 540 && cue.endSeconds > cue.startSeconds
                        && cue.text.components(separatedBy: "\n").count <= lines
                }, "reflow \(language) sai span/số dòng")
                try expect(zip(output, output.dropFirst()).allSatisfy {
                    $0.endSeconds <= $1.startSeconds + 0.001
                }, "reflow \(language) tạo cue chồng lấn")

                let config = SubtitleLayoutConfiguration(languageCode: language, fontName: "Helvetica",
                    fontSize: 54, containerWidth: 900, maxLines: lines,
                    preferredCharactersPerLine: style.maxCharsPerLine)
                for text in [sample, "Hello.", sample + sample] {
                    let full = SubtitleLayoutEngine.layoutPieces(text, configuration: config)
                    let single = SubtitleLayoutEngine.layoutSingleCue(text, configuration: config)
                    let expected = full.count == 1 && full[0].fits ? full[0] : nil
                    try expect(single == expected, "đo một cue khác layout đầy đủ: \(language)/\(lines)")
                }
            }
        }
    }

    @MainActor
    private static func testLayoutReflowLifecycle() async throws {
        let cue = SRTSegment(id: 1, index: 1, timing: "00:00:00,000 --> 00:00:03,000",
                             startSeconds: 0, endSeconds: 3, text: "Bố cục mới")
        let controller = SubtitleLayoutReflowController(debounceNanoseconds: 0)
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let (stopped, stoppedSignal) = AsyncStream<Void>.makeStream()
        var committed: [String] = []
        controller.schedule(operation: {
            // Nếu operation chạy MainActor thì heartbeat phía dưới không thể chạy.
            startedSignal.yield(())
            while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.002) }
            stoppedSignal.yield(())
            return [cue]
        }, completion: { _ in committed.append("stale") })
        var startIterator = started.makeAsyncIterator()
        _ = await startIterator.next()
        try expect(controller.isRunning, "không hiện trạng thái đang xử lý")
        // Đang ở MainActor trong khi worker vẫn xử lý: UI còn phản hồi.
        controller.schedule(operation: { [cue] }, completion: { result in
            committed.append(result.first?.text ?? "empty")
        })
        var stopIterator = stopped.makeAsyncIterator()
        _ = await stopIterator.next()
        for _ in 0..<200 where controller.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try expect(!controller.isRunning && committed == [cue.text], "kết quả cũ ghi đè hoặc state không kết thúc")

        let debounced = SubtitleLayoutReflowController(debounceNanoseconds: 40_000_000)
        debounced.schedule(operation: { [cue] }, completion: { _ in committed.append("cancelled") })
        debounced.cancel()
        try await Task.sleep(nanoseconds: 60_000_000)
        try expect(!debounced.isRunning && committed == [cue.text], "hủy/chuyển dự án vẫn commit cue")
    }

    private static func testSubtitleQualityAnalyzer() throws {
        let segments = [
            SRTSegment(
                id: 1, index: 1,
                timing: SRTTimecode.makeTiming(start: 0, end: 0.4),
                startSeconds: 0, endSeconds: 0.4,
                text: "Một dòng cực kỳ dài sẽ tràn khỏi vùng an toàn"
            ),
            SRTSegment(
                id: 2, index: 2,
                timing: SRTTimecode.makeTiming(start: 0.3, end: 2),
                startSeconds: 0.3, endSeconds: 2,
                text: "Dòng một\nDòng hai\nDòng ba"
            ),
        ]
        let original = SRTDocument.renderSRT(segments)
        let issues = SubtitleQualityAnalyzer.analyze(
            segments,
            configuration: SubtitleLayoutConfiguration(
                languageCode: "vi",
                fontName: "Helvetica",
                fontSize: 54,
                containerWidth: 280,
                maxLines: 2,
                preferredCharactersPerLine: 33,
                explicitBreakPolicy: .preserve
            )
        )
        try expect(issues.contains { $0.cueID == 1 && $0.code == .lineOverflow }, "QC bỏ sót text tràn")
        try expect(issues.contains { $0.cueID == 1 && $0.code == .tooShort }, "QC bỏ sót cue quá ngắn")
        try expect(issues.contains { $0.cueID == 1 && $0.code == .overlap }, "QC bỏ sót timing chồng")
        try expect(issues.contains { $0.cueID == 2 && $0.code == .tooManyLines }, "QC bỏ sót dòng thứ ba")
        try expect(SRTDocument.renderSRT(segments) == original, "QC không được mutate subtitle")
    }

    private static func testProjectPaths() throws {
        let media = URL(fileURLWithPath: "/tmp/Phim Nhật 01.mov")
        try expect(
            ProjectBackupPathPolicy.projectFolderSlug(for: media) == "Phim_Nhật_01",
            "slug dự án thay đổi"
        )
        try expect(
            ProjectBackupPathPolicy.projectID(for: media)
                == ProjectBackupPathPolicy.projectID(for: media),
            "project id không ổn định"
        )
        try expect(
            ProjectBackupPathPolicy.coLocatedDeliverableURL(
                for: media,
                targetLang: " VI ",
                extension: "srt"
            ).path == "/tmp/Phim Nhật 01_vi.srt",
            "tên bản dịch cạnh media sai"
        )

        let bundled = URL(fileURLWithPath: "/tmp/Phim Nhật 01/Phim Nhật 01.mov")
        try expect(
            ProjectBackupPathPolicy.exportBundleDir(for: bundled).path
                == "/tmp/Phim Nhật 01",
            "media đã ở trong bundle nhưng vẫn bị lồng thư mục"
        )
    }

    private static func testFakeTranslation() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let input = temp.appendingPathComponent("input.srt")
        let output = temp.appendingPathComponent("output.srt")
        try """
        1
        00:00:01,000 --> 00:00:02,000
        Hello

        2
        00:00:02,100 --> 00:00:03,000
        Goodbye
        """.write(to: input, atomically: true, encoding: .utf8)

        let client = StubAIClient(
            response: """
            ```json
            {"translations":[{"id":0,"text":"Xin chào"},{"id":1,"text":"Tạm biệt"}]}
            ```
            """
        )
        try await CloudAIWorkflow.translateSRT(
            input: input,
            output: output,
            targetLanguage: "vi",
            sourceLanguage: "en",
            progress: { _ in },
            client: client
        )

        try expect(client.requests.count == 1, "dịch phải gửi đúng một request")
        let request = try require(client.requests.first, "không ghi nhận request")
        try expect(request.expectsJSON, "dịch phải yêu cầu JSON")
        try expect(
            (request.maxOutputTokens ?? 0) >= 512 && (request.maxOutputTokens ?? .max) <= 3_000,
            "completion reservation dịch phải theo kích thước chunk"
        )
        try expect(
            request.user.contains("Hello") && request.user.contains("Goodbye"),
            "không gửi đầy đủ SRT trong một request"
        )

        let translated = try String(contentsOf: output, encoding: .utf8)
        try expect(translated.contains("Xin chào"), "thiếu block dịch đầu")
        try expect(translated.contains("Tạm biệt"), "thiếu block dịch cuối")
        try expect(
            translated.contains("00:00:01,000 --> 00:00:02,000"),
            "bản dịch làm đổi timing"
        )
    }

    private static func testLongTranslationChunks() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let input = temp.appendingPathComponent("long.srt")
        let output = temp.appendingPathComponent("long_vi.srt")
        let source = (0..<80).map { index in
            """
            \(index + 1)
            00:00:00,000 --> 00:00:01,000
            This is subtitle line \(index), designed to make the translation request long enough for chunking.
            """
        }.joined(separator: "\n\n")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let client = TranslationEchoStub()
        try await CloudAIWorkflow.translateSRT(
            input: input,
            output: output,
            targetLanguage: "vi",
            sourceLanguage: "en",
            progress: { _ in },
            client: client
        )

        try expect(client.requests.count > 1, "SRT dài phải tự chia nhiều request")
        try expect(
            client.requests.allSatisfy { ($0.maxOutputTokens ?? 0) <= 3_000 },
            "mỗi phần dịch phải giữ completion reservation an toàn"
        )
        let result = try String(contentsOf: output, encoding: .utf8)
        try expect(result.contains("VI 0") && result.contains("VI 79"), "ráp lại bị thiếu cue dịch")
        try expect(result.contains("00:00:00,000 --> 00:00:01,000"), "chunking làm đổi timing SRT")
    }

    private static func testIncompleteTranslation() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let input = temp.appendingPathComponent("input.srt")
        let output = temp.appendingPathComponent("output.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        One

        2
        00:00:01,000 --> 00:00:02,000
        Two
        """.write(to: input, atomically: true, encoding: .utf8)

        let client = RepairClient { _, attempt in
            attempt == 1 ? #"{"translations":[{"id":0,"text":"Một"}]}"# : #"{"translations":[]}"#
        }
        do {
            try await CloudAIWorkflow.translateSRT(
                input: input,
                output: output,
                targetLanguage: "vi",
                sourceLanguage: "en",
                progress: { _ in },
                client: client
            )
            throw TestFailure(description: "AI trả thiếu block nhưng không báo lỗi")
        } catch CloudAIError.incompleteTranslation {
            try expect(client.count == 3, "phải giới hạn ở hai lượt bổ sung")
            try expect(
                !FileManager.default.fileExists(atPath: output.path),
                "lỗi vẫn ghi file dịch dở"
            )
        }
    }

    private static func testIncompleteTranslationRecovery() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let input = temp.appendingPathComponent("input.srt")
        let output = temp.appendingPathComponent("output.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        One

        2
        00:00:01,000 --> 00:00:02,000
        Two
        """.write(to: input, atomically: true, encoding: .utf8)

        let client = MissingThenRecoveringTranslationStub()
        try await CloudAIWorkflow.translateSRT(
            input: input,
            output: output,
            targetLanguage: "vi",
            sourceLanguage: "en",
            progress: { _ in },
            client: client
        )

        try expect(client.requests.count == 2, "chỉ được gửi lại cue thiếu")
        let recoveryPrompt = client.requests[1].user
        let inputRange = try require(recoveryPrompt.range(of: "INPUT:\n"), "prompt bổ sung thiếu INPUT")
        let recoveryInput = String(recoveryPrompt[inputRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryItems = try JSONDecoder().decode(
            [TestTranslationRequest].self,
            from: Data(recoveryInput.utf8)
        )
        try expect(
            recoveryItems.map(\.id) == [1] && recoveryItems.first?.text == "Two",
            "request bổ sung vẫn gửi lại cue đã dịch"
        )
        let translated = try String(contentsOf: output, encoding: .utf8)
        try expect(translated.contains("Một") && translated.contains("Hai"), "không ráp đủ kết quả bổ sung")
    }

    private static func testFakeSummary() async throws {
        let client = StubAIClient(response: "  Tóm tắt thử.  ")
        let result = try await CloudAIWorkflow.summarize(
            transcript: "Nội dung dài cần tóm tắt.",
            sourceLanguageHint: "vi",
            outputLanguage: "vi",
            client: client
        )
        try expect(result == "Tóm tắt thử.", "không trim kết quả tóm tắt")
        try expect(client.requests.count == 1, "tóm tắt phải gửi đúng một request")
        let request = try require(client.requests.first, "không ghi nhận request")
        try expect(!request.expectsJSON, "tóm tắt không cần JSON")
        try expect(request.maxOutputTokens == 1_200, "trần output tóm tắt bị thay đổi")
    }

    private static func testSemanticCuePlanning() async throws {
        let words = semanticTestWords()
        let client = StubAIClient(response: #"{"plans":[{"blockID":0,"boundaryWordIDs":[7,17]}]}"#)
        let local = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "en")
        let result = await SemanticCueWorkflow.refine(words: words, localSegments: local, languageCode: "en", client: client)
        try expect(client.requests.count == 1, "cụm mơ hồ phải gọi đúng một request semantic")
        try expect(result.refinedBlockCount == 1 && result.fallbackBlockCount == 0, "proposal hợp lệ không được fallback")
        try expect(result.segments.count == 2, "boundary AI không dựng đúng hai cue")
        let rebuilt = result.segments.map(\.text).joined(separator: " ")
        try expect(rebuilt == words.map(\.text).joined(separator: " "), "semantic planner làm đổi hoặc mất từ")
        try expect(result.segments.allSatisfy { $0.endSeconds - $0.startSeconds <= 6.001 }, "semantic planner tạo cue quá sáu giây")
    }

    private static func testSemanticCueFallback() async throws {
        let words = semanticTestWords()
        let local = SpeechWordTimingProcessor.makeSegments(from: words, languageCode: "en")
        let client = StubAIClient(response: #"{"plans":[{"blockID":0,"boundaryWordIDs":[0,17]}]}"#)
        let result = await SemanticCueWorkflow.refine(words: words, localSegments: local, languageCode: "en", client: client)
        try expect(result.refinedBlockCount == 0 && result.fallbackBlockCount == 1, "proposal cue cụt phải bị loại")
        try expect(result.segments.map(\.text) == local.map(\.text), "fallback không giữ nguyên kế hoạch local")
        try expect(result.segments.map(\.timing) == local.map(\.timing), "fallback làm đổi timestamp local")
    }

    private static func semanticTestWords() -> [SpeechWordTimestamp] {
        let tokens = [
            "when", "people", "watch", "this", "story", "they", "should", "understand",
            "why", "the", "decision", "matters", "and", "how", "the", "ending", "changes", "everything",
        ]
        return tokens.enumerated().map { index, token in
            let start = Double(index) * 0.43
            return SpeechWordTimestamp(text: token, startSeconds: start, endSeconds: start + 0.34)
        }
    }

    private static func testDubbingProviderCatalog() throws {
        try expect(
            DubbingSpeechProvider.allCases == [.googleCloud, .maziao, .elevenLabs, .appleOffline],
            "thứ tự provider phải là Google → Maziao → ElevenLabs → Apple Offline"
        )
        try expect(GoogleDubbingModel.chirp3HD.voices.contains(where: { $0.id == "vi-VN-Chirp3-HD-Leda" }), "Google phải có giọng Việt Chirp 3 HD")
        try expect(ElevenLabsDubbingModel.v3.rawValue == "eleven_v3", "Eleven v3 dùng sai model id")
        try expect(DubbingSpeechProvider.appleOffline.detail.contains("không tự tải"), "Apple Offline phải ghi rõ không tự tải")
    }

    private static func testDubbingModels() throws {
        let cue = SRTSegment(
            id: 7,
            index: 7,
            timing: SRTTimecode.makeTiming(start: 2, end: 4),
            startSeconds: 2,
            endSeconds: 4,
            text: "Xin chào thế giới"
        )
        let first = DubbingFingerprint.make(
            cue: cue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-a",
            rate: 0.5
        )
        let same = DubbingFingerprint.make(
            cue: cue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-a",
            rate: 0.5
        )
        let changedVoice = DubbingFingerprint.make(
            cue: cue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-b",
            rate: 0.5
        )
        let changedProvider = DubbingFingerprint.make(
            cue: cue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-a",
            rate: 0.5,
            provider: .googleCloud,
            modelIdentifier: GoogleDubbingModel.chirp3HD.rawValue
        )
        let changedTextCue = SRTSegment(
            id: cue.id,
            index: cue.index,
            timing: cue.timing,
            startSeconds: cue.startSeconds,
            endSeconds: cue.endSeconds,
            text: "Xin chào"
        )
        let changedText = DubbingFingerprint.make(
            cue: changedTextCue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-a",
            rate: 0.5
        )
        try expect(first == same, "fingerprint cùng input phải ổn định")
        try expect(first != changedVoice, "đổi voice phải invalidate cache")
        try expect(first != changedProvider, "đổi provider/model phải invalidate cache")
        try expect(first != changedText, "đổi text phải invalidate cache")
        let retimedCue = SRTSegment(
            id: cue.id,
            index: cue.index,
            timing: SRTTimecode.makeTiming(start: 2, end: 5),
            startSeconds: 2,
            endSeconds: 5,
            text: cue.text
        )
        let retimed = DubbingFingerprint.make(
            cue: retimedCue,
            localeIdentifier: "vi-VN",
            voiceIdentifier: "voice-a",
            rate: 0.5
        )
        try expect(first == retimed, "trim cue không được invalidate clip TTS")

        let naturalShort = DubbingRenderedCue(
            id: cue.id,
            startSeconds: cue.startSeconds,
            endSeconds: 5,
            audioDuration: 1,
            audioURL: URL(fileURLWithPath: "/tmp/dub-natural-short.caf"),
            fingerprint: first
        )
        let naturalLong = DubbingRenderedCue(
            id: cue.id,
            startSeconds: cue.startSeconds,
            endSeconds: cue.endSeconds,
            audioDuration: 2.8,
            audioURL: URL(fileURLWithPath: "/tmp/dub-natural-long.caf"),
            fingerprint: first
        )
        let manualFast = naturalLong.applyingPlaybackRate(1.4)
        let manualSlow = DubbingRenderedCue(
            id: cue.id,
            startSeconds: cue.startSeconds,
            endSeconds: 5,
            audioDuration: 1,
            audioURL: URL(fileURLWithPath: "/tmp/dub-manual-slow.caf"),
            fingerprint: first,
            playbackRateOverride: 0.5
        )
        try expect(naturalShort.playbackRate == 1, "voice ngắn phải mặc định đọc tự nhiên 1×")
        try expect(naturalShort.playedDuration == 1 && naturalShort.fit == .fits, "voice ngắn được kết thúc tự nhiên rồi để im lặng")
        try expect(naturalLong.playbackRate == 1 && naturalLong.fit == .needsReview, "voice dài không được tự tăng tốc")
        try expect(abs(manualFast.playedDuration - 2) < 0.001 && manualFast.fit == .adjusted, "tăng tốc thủ công phải khớp cue")
        try expect(abs(manualSlow.playedDuration - 2) < 0.001 && manualSlow.fit == .adjusted, "giảm tốc thủ công phải được giữ khi còn nằm trong cue")
        let retimedManual = manualFast.updatingTiming(from: retimedCue)
        try expect(abs(retimedManual.playbackRate - 1.4) < 0.001, "trim subtitle không được xóa tốc độ DUB đã chọn")
        try expect(
            !DubbingAudioValidation.isPlausible(duration: 0.011610, text: cue.text),
            "clip Apple chỉ có một buffer không được xem là đã tạo thành công"
        )
        try expect(
            DubbingAudioValidation.isPlausible(duration: 0.42, text: "Vâng."),
            "cue đọc rất ngắn nhưng hợp lệ không được loại khỏi cache"
        )
        try expect(
            abs(DubbingPlaybackMath.expectedAudioTime(for: manualFast, mediaTime: 3) - 1.4) < 0.001,
            "media time không map đúng sang audio time theo manual playback rate"
        )
        try expect(
            DubbingPlaybackMath.expectedAudioTime(for: manualFast, mediaTime: 10) == manualFast.audioDuration,
            "audio time phải được chặn tại cuối clip"
        )
        try expect(
            DubbingPlaybackMath.shouldCorrectDrift(actualAudioTime: 0.7, expectedAudioTime: 1, secondsSinceLastSeek: 0.5),
            "drift lớn sau throttle phải được sửa"
        )
        try expect(
            !DubbingPlaybackMath.shouldCorrectDrift(actualAudioTime: 0.95, expectedAudioTime: 1, secondsSinceLastSeek: 1),
            "drift nhỏ không được seek gây giật"
        )
    }

    private static func testDubbingToolbarAvailability() throws {
        try expect(
            !DubbingToolbarAvailability.canRenderSelected(
                hasSubtitleSelection: false,
                providerReady: true,
                isRendering: false
            ),
            "không có selection SUB thì nút lồng cue phải tắt"
        )
        try expect(
            !DubbingToolbarAvailability.canRenderSelected(
                hasSubtitleSelection: true,
                providerReady: false,
                isRendering: false
            ),
            "provider chưa sẵn sàng thì nút lồng cue phải tắt"
        )
        try expect(
            DubbingToolbarAvailability.canRenderSelected(
                hasSubtitleSelection: true,
                providerReady: true,
                isRendering: false
            ),
            "selection SUB hợp lệ phải bật nút lồng cue"
        )
        try expect(
            !DubbingToolbarAvailability.canRenderAll(
                hasCues: true,
                providerReady: true,
                isRendering: true
            ),
            "đang render thì không được khởi tạo thêm lượt lồng toàn bộ"
        )
    }

    private static func testMaziaoVoiceSelectionPolicy() throws {
        let voices = [
            MaziaoVoiceDescriptor(
                id: "lingual-voice",
                name: "Lingual",
                language: "vi-VN",
                gender: "female",
                previewURL: nil,
                modelID: MaziaoDubbingModel.lingualV2.rawValue
            ),
            MaziaoVoiceDescriptor(
                id: "vieten-voice",
                name: "VietEN",
                language: "vi-VN",
                gender: "male",
                previewURL: nil,
                modelID: MaziaoDubbingModel.vieten.rawValue
            ),
        ]
        let restored = MaziaoVoiceSelectionPolicy.reconcile(
            voices: voices,
            currentVoiceID: "vieten-voice",
            currentModel: .lingualV2
        )
        try expect(restored.voiceID == "vieten-voice" && restored.model == .vieten, "voice đã lưu phải quyết định đúng model")

        let switched = MaziaoVoiceSelectionPolicy.selectingModel(
            .lingualV2,
            voices: voices,
            currentVoiceID: "vieten-voice"
        )
        try expect(switched.voiceID == "lingual-voice" && switched.model == .lingualV2, "đổi model phải chọn voice tương thích")

        let selected = MaziaoVoiceSelectionPolicy.selectingVoice(
            "vieten-voice",
            voices: voices,
            currentModel: .lingualV2
        )
        try expect(selected.model == .vieten, "đổi voice phải đồng bộ model của voice")
    }

    private static func testDubbingVoiceCatalogGrouping() throws {
        let voices = [
            DubbingVoiceCatalogItem(id: "vi-1", name: "Lan", language: "vi-VN", detail: "female"),
            DubbingVoiceCatalogItem(id: "us-1", name: "Rachel", language: "en-US", detail: "female"),
            DubbingVoiceCatalogItem(id: "gb-1", name: "Arthur", language: "en-GB", detail: "male"),
            DubbingVoiceCatalogItem(id: "ko-1", name: "Min", language: "ko-KR", detail: "male"),
        ]
        let all = DubbingVoiceCatalogPolicy.groups(
            voices: voices,
            query: "",
            interfaceLocaleIdentifier: "vi"
        )
        try expect(all.count == 4, "phải tách bốn cụm quốc gia/ngôn ngữ")

        let vietnam = DubbingVoiceCatalogPolicy.groups(
            voices: voices,
            query: "Viet Nam",
            interfaceLocaleIdentifier: "vi"
        )
        try expect(vietnam.count == 1 && vietnam[0].voices.map(\.id) == ["vi-1"], "tìm tên nước phải bỏ dấu")

        let voiceName = DubbingVoiceCatalogPolicy.groups(
            voices: voices,
            query: "rachel",
            interfaceLocaleIdentifier: "en"
        )
        try expect(voiceName.count == 1 && voiceName[0].voices.first?.id == "us-1", "phải tìm được tên giọng")
        try expect(
            DubbingVoiceCatalogPolicy.canonicalLocaleIdentifier(for: "zh") == "zh-CN",
            "locale thiếu vùng phải suy ra quốc gia phổ biến"
        )
    }

    private static func testCloudVoiceCatalogDecoders() throws {
        let google = try GoogleVoiceCatalogDecoder.voices(from: fixtureData("google-voices.json"))
        try expect(google.count == 2, "Google phải decode đủ giọng")
        try expect(google[0].language == "vi-VN" && google[0].name == "Leda", "Google mất locale/tên giọng")
        try expect(GoogleDubbingModel.chirp3HD.matches(voiceIdentifier: google[0].id), "Google model filter sai")

        let eleven = try ElevenLabsVoiceCatalogDecoder.page(from: fixtureData("eleven-voices-page.json"))
        try expect(eleven.hasMore && eleven.nextPageToken == "page-2-fixture", "ElevenLabs mất token phân trang")
        try expect(eleven.totalCount == 2 && eleven.voices.count == 1, "ElevenLabs mất tổng số giọng")
        try expect(eleven.voices[0].language == "ko-KR", "ElevenLabs phải ưu tiên verified locale")
        try expect(eleven.voices[0].modelIDs.contains("eleven_v3"), "ElevenLabs mất model ID")
    }

    private static func testDubbingCueMergePreservation() async throws {
        let previous = [
            SRTSegment(id: 1, index: 1, timing: SRTTimecode.makeTiming(start: 0, end: 1), startSeconds: 0, endSeconds: 1, text: "Một"),
            SRTSegment(id: 2, index: 2, timing: SRTTimecode.makeTiming(start: 1.2, end: 2), startSeconds: 1.2, endSeconds: 2, text: "Hai"),
            SRTSegment(id: 3, index: 3, timing: SRTTimecode.makeTiming(start: 2.2, end: 3), startSeconds: 2.2, endSeconds: 3, text: "Ba"),
            SRTSegment(id: 4, index: 4, timing: SRTTimecode.makeTiming(start: 3.2, end: 4), startSeconds: 3.2, endSeconds: 4, text: "Bốn"),
        ]
        let updated = try require(
            SRTSegmentEditor.mergeAdjacent(in: previous, ids: [1, 2, 3]),
            "fixture không gộp được cue"
        )
        let plan = try require(
            DubbingMergePreservationPlan.make(
                previousCues: previous,
                updatedCues: updated,
                mergedSourceIDs: [1, 2, 3]
            ),
            "không lập được kế hoạch giữ audio khi gộp cue"
        )
        try expect(plan.sourceCues.map(\.id) == [1, 2, 3], "kế hoạch ghép sai cue nguồn")
        try expect(plan.mergedCue.id == 1, "cue ghép phải giữ id đầu")
        try expect(
            plan.unaffectedCues.count == 1
                && plan.unaffectedCues[0].previous.id == 4
                && plan.unaffectedCues[0].updated.id == 2,
            "DUB phía sau phải được chuyển từ id cũ sang id mới"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-dub-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.caf")
        let secondURL = directory.appendingPathComponent("second.caf")
        let thirdURL = directory.appendingPathComponent("third.caf")
        let outputURL = directory.appendingPathComponent("merged.m4a")
        try writeDubbingMergeTone(to: firstURL, duration: 0.16, frequency: 330)
        try writeDubbingMergeTone(to: secondURL, duration: 0.12, frequency: 440)
        try writeDubbingMergeTone(to: thirdURL, duration: 0.12, frequency: 550)

        _ = try await DubbingAudioMergeService.merge(
            clips: [
                DubbingAudioMergeClip(audioURL: firstURL, startOffset: 0, playbackRate: 1),
                DubbingAudioMergeClip(audioURL: secondURL, startOffset: 0.08, playbackRate: 1),
                DubbingAudioMergeClip(audioURL: thirdURL, startOffset: 0.35, playbackRate: 2),
            ],
            outputURL: outputURL
        )
        let duration = await DubbingCacheStore.audioDuration(at: outputURL)
        try expect(FileManager.default.fileExists(atPath: outputURL.path), "ghép cue không tạo audio cache")
        try expect(duration >= 0.39 && duration <= 0.55, "audio ghép không giữ overlap, khoảng nghỉ hoặc tốc độ cue")
        let player = try AVAudioPlayer(contentsOf: outputURL)
        try expect(player.prepareToPlay(), "audio cue đã ghép không mở được để phát")
    }

    private static func testDubbingCacheUsage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-dub-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DubbingCacheStore(rootURL: directory)
        let sourceURL = store.clipURL(for: "source")
        let aliasURL = store.clipURL(for: "alias")
        let mergedURL = store.mergedClipURL(for: "merged")
        try Data(repeating: 0x7f, count: 32_000).write(to: sourceURL)
        try FileManager.default.linkItem(at: sourceURL, to: aliasURL)
        try Data(repeating: 0x3a, count: 17_000).write(to: mergedURL)
        try Data(repeating: 0x55, count: 9_000).write(
            to: directory.appendingPathComponent("ignore.tmp")
        )

        let usage = try store.usage()
        try expect(usage.clipCount == 3, "cache phải đếm đủ CAF/M4A hiển thị")
        try expect(usage.storedFileCount == 2, "hard-link cache không được tính đôi dung lượng đĩa")
        try expect(usage.allocatedBytes > 0, "cache có file nhưng báo dung lượng bằng 0")
        try expect(store.existingClipURL(for: "merged") == mergedURL, "cache không nhận clip merge M4A")
    }

    private static func writeDubbingMergeTone(
        to url: URL,
        duration: Double,
        frequency: Double
    ) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        ) else {
            throw TestFailure(description: "không tạo được format audio test")
        }
        let frameCount = AVAudioFrameCount((duration * format.sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else {
            throw TestFailure(description: "không tạo được buffer audio test")
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let phase = 2 * Double.pi * frequency * Double(frame) / format.sampleRate
            samples[frame] = Float(sin(phase) * 0.15)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func testMaziaoResponseFixtures() throws {
        let credits = try MaziaoResponseDecoder.remainingCredits(
            from: fixtureData("maziao-account.json")
        )
        try expect(credits == 198_765, "account fixture mất remaining credits")

        let voices = try MaziaoResponseDecoder.voices(
            from: fixtureData("maziao-voices.json")
        )
        let voicePage = try MaziaoResponseDecoder.voicePage(
            from: fixtureData("maziao-voices.json")
        )
        try expect(
            voicePage.total == 2 && voicePage.limit == 100 && voicePage.offset == 0,
            "voice fixture mất metadata phân trang"
        )
        try expect(voices.count == 2, "voice fixture phải có hai giọng")
        try expect(voices[0].id == "voice-vi-fixture", "voice id bị đổi khi decode")
        try expect(voices[0].language == "vi-VN", "voice language bị mất")
        try expect(voices[0].modelID == "lingual_speech_v2", "voice modelId bị mất")
        try expect(
            voices[0].previewURL?.absoluteString == "https://cdn.example.invalid/voice-vi.mp3",
            "voice preview URL bị mất"
        )
        try expect(voices[1].gender == "—", "field tùy chọn thiếu phải fallback an toàn")

        let snakeCasePreview = try MaziaoResponseDecoder.voices(from: Data(#"""
        {
          "data": {"items": [{
            "id": "voice-snake-fixture",
            "name": "Snake Preview",
            "preview_url": "https://cdn.example.invalid/voice-snake.mp3"
          }]}
        }
        """#.utf8))
        try expect(
            snakeCasePreview.first?.previewURL?.absoluteString == "https://cdn.example.invalid/voice-snake.mp3",
            "voice preview_url phải được hỗ trợ"
        )

        let nestedPreview = try MaziaoResponseDecoder.voice(from: Data(#"""
        {
          "data": {
            "id": "voice-nested-fixture",
            "name": "Nested Preview",
            "media": {
              "audioPreviewUrl": "https://cdn.example.invalid/voice-nested.m4a",
              "previewImageUrl": "https://cdn.example.invalid/voice-nested.jpg"
            }
          }
        }
        """#.utf8))
        try expect(
            nestedPreview.previewURL?.absoluteString == "https://cdn.example.invalid/voice-nested.m4a",
            "voice detail phải tìm được URL audio preview lồng nhau"
        )

        let receipt = try MaziaoResponseDecoder.submitReceipt(
            from: fixtureData("maziao-submit.json")
        )
        try expect(receipt.taskID == "task-fixture-001", "submit fixture mất task id")
        try expect(receipt.remainingCredits == 198_642, "submit fixture mất credits")
    }

    private static func testMaziaoTaskStatusFixtures() throws {
        let pending = try MaziaoResponseDecoder.taskStates(
            from: fixtureData("maziao-status-pending.json")
        )
        try expect(pending.count == 1 && pending[0].status == "processing", "pending status bị decode sai")
        try expect(pending[0].resultURL == nil && pending[0].resultURLs.isEmpty, "pending không được có audio URL")

        let completed = try MaziaoResponseDecoder.taskStates(
            from: fixtureData("maziao-status-completed.json")
        )
        try expect(completed.count == 1 && completed[0].status == "completed", "completed status bị decode sai")
        try expect(
            completed[0].resultURLs.first?.absoluteString == "https://cdn.example.invalid/task-fixture-001.wav",
            "completed fixture mất audio URL"
        )
    }

    private static func testMaziaoSubmitRequestSchema() throws {
        let sourceText = String(repeating: "Nội dung kiểm thử hợp đồng Maziao. ", count: 4)
        let data = try MaziaoRequestEncoder.submitBody(
            text: sourceText,
            voiceID: "voice-vi-fixture",
            modelID: "lingual_speech_v2",
            speed: 1
        )
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let parts = payload?["parts"] as? [[String: Any]]
        let config = payload?["config"] as? [String: Any]
        try expect(payload?["mode"] as? String == "paragraph", "submit sai mode")
        try expect(payload?["voiceId"] as? String == "voice-vi-fixture", "submit thiếu voiceId")
        try expect(parts?.first?["text"] as? String == sourceText, "part thiếu text")
        try expect(parts?.first?["voiceId"] as? String == "voice-vi-fixture", "part thiếu voiceId theo web client")
        try expect(parts?.first?["startTime"] as? Int == 0, "part thiếu startTime")
        try expect(config?["speed"] as? Double == 1, "config thiếu speed")
        try expect(payload?["modelId"] as? String == "lingual_speech_v2", "submit thiếu modelId")
        try expect(payload?["previewText"] as? String != nil, "submit thiếu previewText")
    }

    private static func testMaziaoValidationErrorMessage() throws {
        let data = Data(#"{"detail":[{"loc":["body","parts",0,"voiceId"],"msg":"Field required","input":{"secret":"must not leak"}}]}"#.utf8)
        let message = MaziaoResponseDecoder.providerErrorMessage(from: data, statusCode: 422)
        try expect(message == "Maziao HTTP 422: parts.0.voiceId: Field required", "validation detail chưa dễ hiểu")
        try expect(!message.contains("secret"), "thông báo lỗi không được lộ payload")
    }

    private static func testMaziaoErrorEnvelope() throws {
        let auth = Data(#"{"data":null,"errors":["Authentication required"]}"#.utf8)
        try expect(MaziaoResponseDecoder.providerErrorMessage(from: auth, statusCode: 401, operation: .account)
            == "Maziao HTTP 401 [auth/me]: Authentication required", "errors array bị bỏ mất")
        let validation = Data(#"{"data":null,"errors":["Invalid voice","Unsupported model"]}"#.utf8)
        for status in [400, 422, 442] {
            try expect(MaziaoResponseDecoder.providerErrorMessage(from: validation, statusCode: status, operation: .submit)
                == "Maziao HTTP \(status) [tts/submit]: Invalid voice · Unsupported model", "phải giữ mã HTTP và lý do")
        }
        let nested = Data(#"{"data":{"error":{"errors":[{"message":"Task rejected"}]}}}"#.utf8)
        try expect(MaziaoResponseDecoder.providerErrorMessage(from: nested, statusCode: 400, operation: .status)
            == "Maziao HTTP 400 [tts/status]: Task rejected", "mất lỗi lồng nhau")
        let legacy = Data(#"{"message":"Request rejected"}"#.utf8)
        try expect(MaziaoResponseDecoder.providerErrorMessage(from: legacy, statusCode: 400)
            == "Maziao HTTP 400: Request rejected", "mất message legacy")
    }

    private static func testMaziaoErrorBoundary() throws {
        for raw in [
            #"{"errors":[],"input":{"message":"secret"},"request":{"errors":["secret"]},"metadata":{"error":"secret"}}"#,
            #"{"errors":[" ",null,5],"data":null}"#,
            "<html>private gateway content</html>"
        ] {
            try expect(MaziaoResponseDecoder.providerErrorMessage(from: Data(raw.utf8), statusCode: 442)
                == "Maziao HTTP 442", "fallback không được phản chiếu payload hoặc sửa mã HTTP")
        }
        let longErrors = try JSONSerialization.data(withJSONObject: ["errors": Array(repeating: String(repeating: "x", count: 1000), count: 100)])
        let message = MaziaoResponseDecoder.providerErrorMessage(from: longErrors, statusCode: 422)
        try expect(message.count <= "Maziao HTTP 422: ".count + 1200, "thông báo lỗi quá dài")
        var deep: [String: Any] = ["message": "too deep"]
        for _ in 0..<20 { deep = ["error": deep] }
        let data = try JSONSerialization.data(withJSONObject: deep)
        try expect(MaziaoResponseDecoder.providerErrorMessage(from: data, statusCode: 400)
            == "Maziao HTTP 400", "đọc lỗi phải có giới hạn độ sâu")
    }

    private static func maziaoRequest(_ id: Int, text: String, voice: String = "voice-fixture") -> DubbingSpeechRequest {
        DubbingSpeechRequest(cueID: id, text: text, localeIdentifier: "vi-VN", voiceIdentifier: voice,
            rate: 0.5, outputURL: URL(fileURLWithPath: "/tmp/maziao-fixture-\(id).caf"),
            provider: .maziao, modelIdentifier: "lingual_speech_v2")
    }

    private static func testMaziaoVoicePageMetadata() throws {
        let page = try MaziaoResponseDecoder.voicePage(from: fixtureData("maziao-voices.json"))
        try expect(page.voices.count == 2, "trang giọng Maziao mất items")
        try expect(page.total == 2 && page.limit == 100 && page.offset == 0, "metadata trang Maziao bị đổi")
    }

    private static func testMaziaoLengthBoundary() throws {
        for count in [1, 99, 100] {
            do {
                _ = try MaziaoRequestEncoder.submitBody(text: String(repeating: "a", count: count), voiceID: "v", modelID: "m", speed: 1)
                throw TestFailure(description: "phải chặn text <= 100 trước API")
            } catch MaziaoTextError.tooShort { }
        }
        for count in [101, 249999] { try MaziaoTextPolicy.validate([String(repeating: "a", count: count)]) }
        do {
            try MaziaoTextPolicy.validate([String(repeating: "a", count: 250000)])
            throw TestFailure(description: "phải chặn text >= 250000")
        } catch MaziaoTextError.tooLong { }
        do {
            try MaziaoTextPolicy.validate(["   "])
            throw TestFailure(description: "không chấp nhận whitespace")
        } catch DubbingError.emptyText { }
        let text = String(repeating: "Xin chào. ", count: 12)
        let data = try MaziaoRequestEncoder.submitBody(text: text, voiceID: "v", modelID: "m", speed: 1)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expect((body?["parts"] as? [[String: Any]])?.first?["text"] as? String == text, "không được pad/trim/sửa lời")
    }

    private static func testMaziaoBatchPlanning() throws {
        let texts = (0..<70).map { "Câu \($0): " + String(repeating: "a", count: 20) }
        let requests = texts.enumerated().map { maziaoRequest($0.offset, text: $0.element) }
        let batches = try MaziaoBatchPlanner.batches(for: requests)
        try expect(batches.count > 1, "phải chia nhóm để giới hạn tài nguyên")
        try expect(batches.flatMap { $0 }.map(\.cueID) == requests.map(\.cueID), "batch mất/đảo/lặp cue")
        try expect(batches.flatMap { $0 }.map(\.text) == texts, "batch sửa nội dung")
        for batch in batches { try MaziaoTextPolicy.validate(batch.map(\.text)) }
        // 32 short parts trigger a flush; the trailing tiny cue must be merged back.
        let tail = (0..<33).map { maziaoRequest($0, text: $0 == 32 ? "Hi" : "Xin chào.") }
        let merged = try MaziaoBatchPlanner.batches(for: tail)
        try expect(merged.count == 1 && merged[0].count == 33, "nhóm đuôi ngắn chưa gộp")
        let huge = (0..<3).map { maziaoRequest($0, text: String(repeating: "a", count: 120000)) }
        let hugeBatches = try MaziaoBatchPlanner.batches(for: huge)
        try expect(hugeBatches.count == 3, "tổng nhiều lượt được vượt 250000")
        do {
            _ = try MaziaoBatchPlanner.batches(for: [maziaoRequest(1, text: "Xin chào.")])
            throw TestFailure(description: "một câu ngắn phải báo chọn thêm nội dung")
        } catch MaziaoTextError.tooShort { }
        let emptyBatches = try MaziaoBatchPlanner.batches(for: [])
        try expect(emptyBatches.isEmpty, "cache toàn bộ không cần request")
    }

    private static func testMaziaoBatchRequest() throws {
        let requests = (0..<3).map { maziaoRequest($0, text: "Câu \($0): " + String(repeating: "x", count: 40)) }
        let data = try MaziaoRequestEncoder.batchBody(requests)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let parts = body?["parts"] as? [[String: Any]]
        try expect(body?["mode"] as? String == "multiParts", "sai mode batch")
        try expect(parts?.compactMap { $0["text"] as? String } == requests.map(\.text), "multiParts phải giữ từng câu")
        try expect(parts?.allSatisfy { $0["voiceId"] as? String == "voice-fixture" && $0["speed"] as? Double == 1 } == true, "mất voice/speed")
        do {
            _ = try MaziaoRequestEncoder.batchBody([requests[0], maziaoRequest(9, text: String(repeating: "x", count: 120), voice: "different")])
            throw TestFailure(description: "không được trộn voice trong lượt")
        } catch MaziaoTextError.incompatibleBatch { }
    }

    private static func testMaziaoBatchResults() throws {
        let normal = Data(#"{"data":[{"id":"task","status":"completed","resultUrls":["https://audio.invalid/0.wav","https://audio.invalid/1.wav"]}]}"#.utf8)
        let encoded = Data(#"{"data":[{"id":"task","status":"completed","resultUrl":"[\"https://audio.invalid/0.wav\",\"https://audio.invalid/1.wav\"]"}]}"#.utf8)
        for data in [normal, encoded] {
            let states = try MaziaoResponseDecoder.taskStates(from: data)
            let state = try require(states.first, "thiếu task")
            let urls = try MaziaoResponseDecoder.audioURLs(from: state, expectedCount: 2)
            try expect(urls.map(\.lastPathComponent) == ["0.wav", "1.wav"], "thứ tự tệp sai")
            for expected in [1, 3] {
                do {
                    _ = try MaziaoResponseDecoder.audioURLs(from: state, expectedCount: expected)
                    throw TestFailure(description: "không được gán thiếu/thừa tệp")
                } catch MaziaoTextError.missingResults { }
            }
        }
        let unsafe = MaziaoTaskState(id: "task", status: "completed", resultURL: URL(string: "file:///tmp/audio.wav"), resultURLs: [])
        do {
            _ = try MaziaoResponseDecoder.audioURLs(from: unsafe, expectedCount: 1)
            throw TestFailure(description: "result URL phải HTTPS")
        } catch MaziaoTextError.invalidResultURL { }
    }

    private static func testCloudAudioImmediatePlayback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("msm-audio-handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("provider.wav")
        let format = try require(
            AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
            "không tạo được format fixture"
        )
        let source = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
        let frameCount: AVAudioFrameCount = 6_000
        let buffer = try require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            "không tạo được audio buffer fixture"
        )
        buffer.frameLength = frameCount
        if let samples = buffer.floatChannelData?[0] {
            for frame in 0..<Int(frameCount) {
                samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 24_000)) * 0.05
            }
        }
        try source.write(from: buffer)
        source.close()
        let providerAudio = try Data(contentsOf: sourceURL)

        for attempt in 0..<12 {
            let outputURL = directory.appendingPathComponent("preview-\(attempt).caf")
            try await DubbingAudioTranscoder.writeCloudAudio(
                providerAudio,
                sourceExtension: "wav",
                to: outputURL
            )
            let result = try await MainActor.run { () throws -> (Bool, Double, Int) in
                let prepared = try DubbingPreviewAudioLoader.prepare(from: outputURL)
                return (prepared.player.prepareToPlay(), prepared.player.duration, prepared.data.count)
            }
            try expect(result.0, "player không prepare ngay sau transcode")
            try expect(result.1 >= 0.24, "audio sau transcode bị cụt")
            try expect(result.2 > 4_096, "CAF sau transcode chỉ còn header")
        }

        if let fixturePath = ProcessInfo.processInfo.environment["MSM_MAZIAO_LIVE_AUDIO_FIXTURE"],
           !fixturePath.isEmpty {
            let liveData = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
            let liveOutput = directory.appendingPathComponent("maziao-live.caf")
            try await DubbingAudioTranscoder.writeCloudAudio(
                liveData,
                sourceExtension: "wav",
                to: liveOutput
            )
            let live = try await MainActor.run { () throws -> (Bool, Double) in
                let prepared = try DubbingPreviewAudioLoader.prepare(from: liveOutput)
                return (prepared.player.prepareToPlay(), prepared.player.duration)
            }
            try expect(live.0 && live.1 > 0, "tệp Maziao thật không mở/phát ngay sau transcode")
        }
    }

    private static func testMaziaoPollingPolicy() throws {
        let preview = MaziaoPollingPolicy.timeoutSeconds(characterCount: 150, partCount: 1)
        let batch = MaziaoPollingPolicy.timeoutSeconds(characterCount: 4_000, partCount: 32)
        let maximum = MaziaoPollingPolicy.timeoutSeconds(characterCount: 250_000, partCount: 1)
        try expect(preview == 300, "preview phải có ít nhất 5 phút")
        try expect(batch > preview && batch >= 1_300, "batch dài chưa có đủ thời gian xử lý")
        try expect(maximum == 1_800, "timeout phải có trần 30 phút")
        try expect(MaziaoPollingPolicy.pollIntervalSeconds(afterAttempt: 0) == 1, "poll đầu phải phản hồi nhanh")
        try expect(MaziaoPollingPolicy.pollIntervalSeconds(afterAttempt: 10) == 2, "poll trung gian sai")
        try expect(MaziaoPollingPolicy.pollIntervalSeconds(afterAttempt: 25) == 4, "poll dài phải giảm tải")
        try expect(MaziaoPollingPolicy.maximumTransientStatusFailures == 3, "retry mạng phải hữu hạn")
    }

    private static func testMaziaoInvalidResponse() throws {
        do {
            _ = try MaziaoResponseDecoder.submitReceipt(
                from: Data(#"{"data":{"remainingCredits":100}}"#.utf8)
            )
            throw TestFailure(description: "submit thiếu taskId không được phép decode thành công")
        } catch is TestFailure {
            throw TestFailure(description: "submit thiếu taskId không được phép decode thành công")
        } catch {
            // Expected: transport schema is incomplete.
        }
    }

    private static func testDubbingSpeechReuse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DubbingCacheStore(rootURL: directory)
        try store.prepare()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = SRTSegment(id: 1, index: 1, timing: "", startSeconds: 0, endSeconds: 2, text: "Xin chào\nthế giới")
        let moved = SRTSegment(id: 9, index: 9, timing: "", startSeconds: 10, endSeconds: 12, text: "Xin chào thế giới")
        func fingerprint(_ cue: SRTSegment) -> String {
            DubbingFingerprint.make(cue: cue, localeIdentifier: "vi-VN", voiceIdentifier: "v", rate: 0.5)
        }
        func content(_ cue: SRTSegment) -> String {
            DubbingFingerprint.speechContent(cue: cue, localeIdentifier: "vi-VN", voiceIdentifier: "v",
                rate: 0.5, provider: .appleOffline, modelIdentifier: "apple-system")
        }
        try expect(content(original) == content(moved), "ID/xuống dòng không được làm lại TTS")
        try expect(fingerprint(original) != fingerprint(moved), "composite identity phải riêng từng cue")
        let rewrapped = SRTSegment(id: original.id, index: original.index, timing: original.timing,
                                   startSeconds: original.startSeconds, endSeconds: original.endSeconds, text: moved.text)
        try expect(fingerprint(original) == fingerprint(rewrapped), "1/2 dòng phải giữ cache")
        try Data(repeating: 1, count: 4096).write(to: store.clipURL(for: fingerprint(original)))
        try store.registerSpeechReuse(content: content(original), fingerprint: fingerprint(original))
        let alias = try store.reuseSpeech(content: content(moved), fingerprint: fingerprint(moved))
        try expect(alias != nil && (try store.usage()).storedFileCount == 1, "reuse phải hard-link không nhân dữ liệu")
        try store.blockReuse(for: fingerprint(moved))
        store.removeClip(for: fingerprint(moved))
        try expect(try store.reuseSpeech(content: content(moved), fingerprint: fingerprint(moved)) == nil,
                   "xóa không được tự hồi sinh audio")
        let composite = String(repeating: "a", count: 16)
        try Data([1]).write(to: store.mergedClipURL(for: composite))
        try store.registerSpeechReuse(content: "merged", fingerprint: composite)
        try expect(try store.reuseSpeech(content: "merged", fingerprint: String(repeating: "b", count: 16)) == nil,
                   "audio ghép có gap không được dùng làm giọng thuần")
        let old = DubbingFingerprint.previousContent(cue: original, localeIdentifier: "vi-VN",
            voiceIdentifier: "v", rate: 0.5, provider: .appleOffline, modelIdentifier: "apple-system")
        try Data([3]).write(to: store.clipURL(for: old))
        let migration = try store.migrateClip(from: old, to: String(repeating: "c", count: 16))
        try expect(migration != nil && FileManager.default.fileExists(atPath: store.clipURL(for: old).path),
                   "migration phải giữ cache cũ để rollback")
        try expect(DubbingFingerprint.previousContent(cue: original, localeIdentifier: "vi-VN", voiceIdentifier: "v",
            rate: 0.6, provider: .elevenLabs, modelIdentifier: "eleven_v3").isEmpty,
                   "Eleven speed cũ bị bỏ qua không được migrate sang giọng mới")
    }

    private static func testElevenLabsGenerationSpeed() throws {
        for (rate, expected) in [(Float(0.5), 1.0), (0.38, 0.76), (0.62, 1.2)] {
            var request = maziaoRequest(1, text: "名前と地名をそのまま読む。")
            request = .init(cueID: 1, text: request.text, localeIdentifier: "ja-JP", voiceIdentifier: "voice",
                            rate: rate, outputURL: request.outputURL, provider: .elevenLabs, modelIdentifier: "eleven_v3")
            let body = try JSONSerialization.jsonObject(with: ElevenLabsRequestEncoder.body(request)) as! [String: Any]
            let settings = body["voice_settings"] as! [String: Any]
            try expect(abs((settings["speed"] as! Double) - expected) < 0.001, "speed provider sai")
            try expect(body["text"] as? String == request.text && body["language_code"] as? String == "ja",
                       "encoder không được sửa chữ/ngôn ngữ")
        }
    }

    @MainActor
    private static func testMaziaoTaskRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = MaziaoTaskJournal(rootURL: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = MaziaoTaskJournal.digest(Data("test-key".utf8))
        var submits = 0
        var resumes = 0
        do {
            _ = try await MaziaoTaskRecovery.resolve(journal: journal, account: account, parts: ["a", "b"],
                characterCount: 4_000, submit: {
                submits += 1
                return "test-receipt"
            }, wait: { _ in throw URLError(.timedOut) })
            throw TestFailure(description: "fake timeout không đến caller")
        } catch is URLError { }
        // A new store instance simulates relaunch; recover a short/partial selection in original order.
        let fresh = MaziaoTaskJournal(rootURL: directory)
        let urls = try await MaziaoTaskRecovery.resolve(journal: fresh, account: account, parts: ["b"],
            onResume: { resumes += 1 }, submit: {
            submits += 1
            return "duplicate"
        }, wait: { receipt in
            try expect(receipt.taskID == "test-receipt", "restart không giữ đúng task")
            try expect(receipt.characterCount == 4_000, "resume phần ngắn phải giữ timeout nhóm gốc")
            return [URL(string: "https://audio.invalid/a")!, URL(string: "https://audio.invalid/b")!]
        })
        try expect(submits == 1 && resumes == 1 && urls[0].lastPathComponent == "b",
                   "resume phải không submit, báo stage và giữ vị trí part")
        try expect(try fresh.matching(account: "other-key", parts: ["b"]) == nil, "không trộn tài khoản")
        try expect(try fresh.matching(account: account, parts: ["changed-text"]) == nil, "không trộn nội dung")
        do {
            _ = try await MaziaoTaskRecovery.resolve(journal: fresh, account: account, parts: ["a"],
                submit: { "duplicate" }, wait: { _ in throw CancellationError() })
        } catch is CancellationError { }
        try expect(try fresh.matching(account: account, parts: ["a"]) != nil, "hủy phải giữ receipt")
        let receipt = try fresh.matching(account: account, parts: ["a"])!
        try expect(receipt.indices(for: ["a", "a"]) == nil, "không gán một tệp cho hai parts khác nhau")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let stored = String(decoding: try Data(contentsOf: files[0]), as: UTF8.self)
        try expect(!stored.contains("test-key") && !stored.contains("https:"), "journal không được chứa key/URL")
        try fresh.remove(receipt)
        try expect(try fresh.matching(account: account, parts: ["a"]) == nil, "commit xong phải gỡ receipt")
        try Data("broken".utf8).write(to: directory.appendingPathComponent("corrupt.json"))
        do {
            _ = try fresh.matching(account: account, parts: ["a"])
            throw TestFailure(description: "journal hỏng không được âm thầm gửi lại")
        } catch is DecodingError { }
    }

    @MainActor
    private static func testDubbingRenderQueue() async throws {
        var active = 0
        var peak = 0
        var finished = Set<Int>()
        try await DubbingRenderQueue.run(count: 7, limit: 99, operation: { index in
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(index.isMultiple(of: 2) ? 8 : 2))
        }, completed: { finished.insert($0) })
        try expect(peak == 2 && active == 0 && finished.count == 7, "queue phải giới hạn hai, không mất kết quả")
        var started = 0
        do {
            try await DubbingRenderQueue.run(count: 9, operation: { index in
                started += 1
                active += 1
                defer { active -= 1 }
                if index == 0 { throw URLError(.badServerResponse) }
                try await Task.sleep(for: .seconds(5))
            })
            throw TestFailure(description: "queue nuốt lỗi")
        } catch is URLError { }
        try expect(active == 0 && started <= 2, "lỗi phải hủy worker và không gửi cue tiếp")
        let task = Task {
            try await DubbingRenderQueue.run(count: 9, operation: { _ in
                active += 1
                defer { active -= 1 }
                try await Task.sleep(for: .seconds(5))
            })
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do { try await task.value; throw TestFailure(description: "queue không hủy") }
        catch is CancellationError { }
        try expect(active == 0, "hủy phải đợi worker thoát")
    }

    private static func testDubbingDurationCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("clip.caf")
        let alias = directory.appendingPathComponent("alias.caf")
        let cache = DubbingAudioDurationCache()
        try writeDubbingMergeTone(to: file, duration: 0.2, frequency: 330)
        try FileManager.default.linkItem(at: file, to: alias)
        let first = await cache.duration(at: file)
        let reused = await cache.duration(at: alias)
        try expect(abs(first - 0.2) < 0.02 && first == reused, "duration alias sai")
        try writeDubbingMergeTone(to: file, duration: 0.9, frequency: 440)
        let changed = await cache.duration(at: alias)
        try expect(abs(changed - 0.9) < 0.02, "metadata cũ không được giữ khi audio thay đổi")
        try FileManager.default.removeItem(at: file)
        let missing = await cache.duration(at: file)
        try expect(missing == 0, "tệp đã xóa không được trả duration cũ")
    }

    private static func testDubbingCompressedCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DubbingCacheStore(rootURL: directory)
        try store.prepare()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try fixtureData("dubbing-tone.mp3")
        try await DubbingAudioTranscoder.writeCompressedMP3(data, to: store.clipURL(for: "tone"))
        guard let url = store.existingClipURL(for: "tone") else { throw TestFailure(description: "MP3 mất cache") }
        try expect(url.pathExtension == "mp3" && (try Data(contentsOf: url)) == data, "phải giữ byte MP3 gốc")
        let player = try AVAudioPlayer(contentsOf: url)
        try expect(player.prepareToPlay() && player.duration > 0.3, "MP3 không chuẩn bị phát được")
        let merged = directory.appendingPathComponent("mixed.m4a")
        _ = try await DubbingAudioMergeService.merge(clips: [.init(audioURL: url, startOffset: 0, playbackRate: 1)],
                                                     outputURL: merged)
        let duration = await DubbingCacheStore.audioDuration(at: merged)
        try expect(duration > 0.3, "MP3 không ghép/export được")
        try expect((try store.usage()).clipCount == 2, "usage bỏ sót MP3")
        do {
            try await DubbingAudioTranscoder.writeCompressedMP3(Data([0, 1, 2]), to: store.clipURL(for: "tone"))
            throw TestFailure(description: "accept MP3 lỗi")
        } catch is TestFailure { throw TestFailure(description: "accept MP3 lỗi") }
        catch { }
        try expect((try Data(contentsOf: url)) == data, "lỗi không được phá cache tốt")
    }

    private static func fixtureData(_ name: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile.deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw TestFailure(description: message)
        }
        return value
    }
}

import Foundation

// Included in the main harness file at installation (same private test helpers).
private final class RepairClient: CloudAIClient {
    var count = 0
    let reply: (CloudAIGenerationRequest, Int) throws -> String
    init(_ reply: @escaping (CloudAIGenerationRequest, Int) throws -> String) { self.reply = reply }
    func generate(_ request: CloudAIGenerationRequest) async throws -> String {
        count += 1
        return try reply(request, count)
    }
}

extension MediaSupportCoreTests {
    private static func repairFixture(_ client: any CloudAIClient, succeeds: Bool) async throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.srt")
        let output = folder.appendingPathComponent("output.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nOne\n\n2\n00:00:01,000 --> 00:00:02,000\nTwo\n"
            .write(to: input, atomically: true, encoding: .utf8)
        try "KEEP ORIGINAL".write(to: output, atomically: true, encoding: .utf8)
        var succeeded = false
        do {
            try await CloudAIWorkflow.translateSRT(input: input, output: output, targetLanguage: "vi",
                                                  sourceLanguage: "en", progress: { _ in }, client: client)
            succeeded = true
        } catch {
            if succeeds { throw error }
        }
        try expect(succeeded == succeeds, "unexpected translation outcome")
        let text = try String(contentsOf: output, encoding: .utf8)
        if !succeeds { try expect(text == "KEEP ORIGINAL", "failed job overwrote original") }
        return text
    }

    private static func testGroqResponsePolicy() throws {
        let normal = Data(#"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#.utf8)
        let decoded = try GroqResponsePolicy.decode(normal)
        try expect(decoded == "OK", "normal response failed")
        do {
            _ = try GroqResponsePolicy.decode(Data(#"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#.utf8))
            throw TestFailure(description: "truncated response accepted")
        } catch CloudAIError.truncatedResponse { }
        try expect(GroqResponsePolicy.shouldRetryWithoutStructuredJSON(.http(status: 400, message: "json_validate_failed")), "known code not retried")
        for status in [401, 403, 429, 500] {
            try expect(!GroqResponsePolicy.shouldRetryWithoutStructuredJSON(.http(status: status, message: "json mode")), "unsafe retry")
        }
    }

    private static func testTranslationVariants() async throws {
        for response in [
            #"[{"id":"0","translation":"Một ```json"},{"id":1,"content":"Hai"}]"#,
            #"{"items":[{"id":0,"translatedText":"Một ```json"},{"id":1,"text":"Hai"}]}"#,
            "```json\n" + #"{"results":[{"id":0,"text":"Một ```json"},{"id":1,"text":"Hai"}]}"# + "\n```"
        ] {
            let client = RepairClient { _, _ in response }
            let result = try await repairFixture(client, succeeds: true)
            try expect(result.contains("Một ```json"), "decoder altered literal fence in text")
            try expect(client.count == 1, "valid response retried")
        }
    }

    private static func testTranslationSchemaRepair() async throws {
        for truncated in [false, true] {
            let client = RepairClient { request, index in
                if index == 1 {
                    if truncated { throw CloudAIError.truncatedResponse }
                    return "not JSON"
                }
                let input = request.user.components(separatedBy: "INPUT:\n").last!
                let items = try JSONDecoder().decode([TestTranslationRequest].self, from: Data(input.utf8))
                try expect(items.count == 1, "repair didn't shrink batch")
                return "{\"translations\":[{\"id\":\(items[0].id),\"text\":\"Đúng\"}]}"
            }
            _ = try await repairFixture(client, succeeds: true)
            try expect(client.count == 3, "expected one failed + two smaller batches")
        }
    }

    private static func testTranslationRejectsAmbiguousIDs() async throws {
        for response in [
            #"{"translations":[{"id":0,"text":"a"},{"id":0,"text":"b"},{"id":1,"text":"c"}]}"#,
            #"{"translations":[{"id":0,"text":"a"},{"id":1,"text":"b"},{"id":99,"text":"c"}]}"#,
            #"{"translations":[{"id":0,"text":"a"},{"id":1,"text":"b"}]"#
        ] {
            let client = RepairClient { _, _ in response }
            _ = try await repairFixture(client, succeeds: false)
            try expect(client.count <= 7, "repair retry unbounded")
        }
    }

    private static func testTranslationNoUnsafeRetry() async throws {
        for status in [401, 429, 503] {
            let client = RepairClient { _, _ in throw CloudAIError.http(status: status, message: "fixture") }
            _ = try await repairFixture(client, succeeds: false)
            try expect(client.count == 1, "network/quota/auth was retried")
        }
        let cancelled = RepairClient { _, _ in throw CancellationError() }
        _ = try await repairFixture(cancelled, succeeds: false)
        try expect(cancelled.count == 1, "cancellation was retried")
    }
}
