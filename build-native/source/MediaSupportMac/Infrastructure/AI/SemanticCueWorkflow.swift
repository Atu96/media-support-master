import Foundation

struct SemanticCueWorkflowResult: Sendable {
    let segments: [SRTSegment]
    let refinedBlockCount: Int
    let fallbackBlockCount: Int
}

enum SemanticCueWorkflow {
    private static let maximumWordsPerRequest = 220

    static func refine(
        words: [SpeechWordTimestamp],
        localSegments: [SRTSegment],
        languageCode: String,
        client: any CloudAIClient
    ) async -> SemanticCueWorkflowResult {
        let blocks = SemanticCuePlanner.blocks(from: words, languageCode: languageCode)
        guard !blocks.isEmpty else {
            return .init(segments: [], refinedBlockCount: 0, fallbackBlockCount: 0)
        }
        let candidates = blocks.filter(\.isAmbiguous)
        guard !candidates.isEmpty else {
            return .init(
                segments: reindexed(localSegments),
                refinedBlockCount: 0,
                fallbackBlockCount: 0
            )
        }

        var acceptedByBlockID: [Int: [SRTSegment]] = [:]
        let fallbackCount = 0
        for batch in batches(candidates) {
            do {
                let plans = try await requestPlans(for: batch, languageCode: languageCode, client: client)
                for block in batch {
                    guard let proposal = plans[block.id],
                          let accepted = SemanticCuePlanner.acceptedSegments(
                            proposal: proposal,
                            for: block,
                            languageCode: languageCode
                          ) else {
                        // Hợp đồng là một block lỗi thì giữ local toàn cục.
                        // Dừng ngay để không tiêu thêm thời gian/quota ở batch sau.
                        return SemanticCueWorkflowResult(
                            segments: reindexed(localSegments),
                            refinedBlockCount: 0,
                            fallbackBlockCount: candidates.count
                        )
                    }
                    acceptedByBlockID[block.id] = accepted
                }
            } catch {
                return SemanticCueWorkflowResult(
                    segments: reindexed(localSegments),
                    refinedBlockCount: 0,
                    fallbackBlockCount: candidates.count
                )
            }
        }
        let output = blocks.flatMap { block in
            acceptedByBlockID[block.id]
                ?? SemanticCuePlanner.localSegments(for: block, languageCode: languageCode)
        }
        return SemanticCueWorkflowResult(
            segments: reindexed(output),
            refinedBlockCount: acceptedByBlockID.count,
            fallbackBlockCount: fallbackCount
        )
    }

    private static func requestPlans(
        for blocks: [SemanticCueBlock],
        languageCode: String,
        client: any CloudAIClient
    ) async throws -> [Int: [Int]] {
        let payload = blocks.map { block in
            RequestBlock(
                id: block.id,
                localBoundaryWordIDs: block.localBoundaryWordIDs,
                words: block.words.enumerated().map { index, word in
                    RequestWord(
                        id: index,
                        text: word.text,
                        startMS: Int((word.startSeconds * 1_000).rounded()),
                        endMS: Int((word.endSeconds * 1_000).rounded())
                    )
                }
            )
        }
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else { throw CloudAIError.invalidResponse }
        let prompt = """
        Ngôn ngữ: \(languageCode). Hãy chọn điểm kết thúc cue theo ý nghĩa toàn câu.
        Mỗi word có id và timestamp cố định. Không dịch, không sửa, không thêm hoặc bỏ từ.
        Chỉ trả boundaryWordIDs là id của từ cuối mỗi cue; bắt buộc chứa id cuối block.
        Ưu tiên cụm nghĩa tự nhiên, 2–5 giây; tuyệt đối không vượt 6 giây.
        Tránh để liên từ, giới từ, trợ từ, chủ ngữ hoặc cụm tên/số đứng cô độc.
        localBoundaryWordIDs chỉ là gợi ý hiện tại, được phép đổi khi câu tự nhiên hơn.
        Trả đúng JSON: {"plans":[{"blockID":0,"boundaryWordIDs":[4,10]}]}
        Phải trả đủ đúng \(blocks.count) blockID trong INPUT.

        INPUT:
        \(json)
        """
        let response = try await client.generate(
            CloudAIGenerationRequest(
                system: "Bạn là biên tập viên subtitle đa ngôn ngữ. Chỉ chọn ranh giới giữa các word ID có sẵn và luôn giữ nguyên nội dung.",
                user: prompt,
                expectsJSON: true,
                maxOutputTokens: min(1_600, max(320, blocks.count * 100))
            )
        )
        let envelope = try decode(response)
        let allowed = Set(blocks.map(\.id))
        guard envelope.plans.count == blocks.count else { throw CloudAIError.invalidResponse }
        var result: [Int: [Int]] = [:]
        for plan in envelope.plans {
            guard allowed.contains(plan.blockID), result[plan.blockID] == nil else {
                throw CloudAIError.invalidResponse
            }
            result[plan.blockID] = plan.boundaryWordIDs
        }
        guard result.count == blocks.count else { throw CloudAIError.invalidResponse }
        return result
    }

    private static func batches(_ blocks: [SemanticCueBlock]) -> [[SemanticCueBlock]] {
        var output: [[SemanticCueBlock]] = []
        var current: [SemanticCueBlock] = []
        var wordCount = 0
        for block in blocks {
            if !current.isEmpty, wordCount + block.words.count > maximumWordsPerRequest {
                output.append(current)
                current = []
                wordCount = 0
            }
            current.append(block)
            wordCount += block.words.count
        }
        if !current.isEmpty { output.append(current) }
        return output
    }

    private static func decode(_ raw: String) throws -> ResponseEnvelope {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}") {
            json = String(trimmed[first...last])
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            throw CloudAIError.invalidResponse
        }
        return envelope
    }

    private static func reindexed(_ segments: [SRTSegment]) -> [SRTSegment] {
        SRTSegmentEditor.reindexed(segments)
    }
}

private struct RequestBlock: Encodable {
    let id: Int
    let localBoundaryWordIDs: [Int]
    let words: [RequestWord]
}

private struct RequestWord: Encodable {
    let id: Int
    let text: String
    let startMS: Int
    let endMS: Int
}

private struct ResponseEnvelope: Decodable {
    let plans: [ResponsePlan]
}

private struct ResponsePlan: Decodable {
    let blockID: Int
    let boundaryWordIDs: [Int]
}
