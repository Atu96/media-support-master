import Foundation

struct SemanticCueBlock: Sendable {
    let id: Int
    let words: [SpeechWordTimestamp]
    let localBoundaryWordIDs: [Int]
    let isAmbiguous: Bool
}

enum SemanticCuePlanner {
    static let maximumCueDuration = 6.0
    static let minimumCueDuration = 0.85
    private static let strongPause = 0.62
    private static let maximumWordsPerBlock = 72

    static func blocks(
        from words: [SpeechWordTimestamp],
        languageCode: String
    ) -> [SemanticCueBlock] {
        let valid = words.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.startSeconds.isFinite && $0.endSeconds.isFinite
                && $0.endSeconds > $0.startSeconds
        }.sorted { $0.startSeconds < $1.startSeconds }
        guard !valid.isEmpty else { return [] }

        var strongPauseBlocks: [[SpeechWordTimestamp]] = []
        var pending: [SpeechWordTimestamp] = []
        for word in valid {
            if let previous = pending.last {
                let gap = max(0, word.startSeconds - previous.endSeconds)
                if gap >= strongPause {
                    strongPauseBlocks.append(pending)
                    pending = []
                }
            }
            pending.append(word)
        }
        if !pending.isEmpty { strongPauseBlocks.append(pending) }
        let rawBlocks = strongPauseBlocks.flatMap(splitOversizedBlock)

        return rawBlocks.enumerated().map { id, blockWords in
            let local = SpeechWordTimingProcessor.makeSegments(
                from: blockWords,
                languageCode: languageCode
            )
            let boundaries = localBoundaryIDs(local, words: blockWords)
            return SemanticCueBlock(
                id: id,
                words: blockWords,
                localBoundaryWordIDs: boundaries,
                isAmbiguous: isAmbiguous(words: blockWords, localBoundaries: boundaries)
            )
        }
    }

    static func acceptedSegments(
        proposal: [Int],
        for block: SemanticCueBlock,
        languageCode: String
    ) -> [SRTSegment]? {
        let boundaries = Array(Set(proposal)).sorted()
        guard boundaries == proposal,
              boundaries.last == block.words.count - 1,
              boundaries.count <= block.localBoundaryWordIDs.count + 2,
              boundaries.count >= max(1, block.localBoundaryWordIDs.count - 1),
              let segments = SpeechWordTimingProcessor.makeSegments(
                from: block.words,
                endingWordIndices: boundaries,
                languageCode: languageCode
              ), segments.count == boundaries.count else { return nil }

        for (index, segment) in segments.enumerated() {
            let duration = segment.endSeconds - segment.startSeconds
            guard duration <= maximumCueDuration + 0.001 else { return nil }
            if segments.count > 1, duration < minimumCueDuration { return nil }
            let visibleCharacters = segment.text.filter { !$0.isWhitespace }.count
            if duration > 0, Double(visibleCharacters) / duration > 36 { return nil }
            let startWord = index == 0 ? 0 : boundaries[index - 1] + 1
            let endWord = boundaries[index]
            if endWord == startWord,
               block.words[startWord].text.filter({ !$0.isPunctuation }).count <= 2 {
                return nil
            }
        }
        return segments
    }

    static func localSegments(for block: SemanticCueBlock, languageCode: String) -> [SRTSegment] {
        SpeechWordTimingProcessor.makeSegments(
            from: block.words,
            endingWordIndices: block.localBoundaryWordIDs,
            languageCode: languageCode
        ) ?? SpeechWordTimingProcessor.makeSegments(from: block.words, languageCode: languageCode)
    }

    private static func localBoundaryIDs(
        _ segments: [SRTSegment],
        words: [SpeechWordTimestamp]
    ) -> [Int] {
        guard !words.isEmpty else { return [] }
        var output: [Int] = []
        var searchStart = 0
        for segment in segments {
            var best = searchStart
            while best + 1 < words.count,
                  words[best + 1].endSeconds <= segment.endSeconds + 0.08 {
                best += 1
            }
            output.append(best)
            searchStart = min(words.count - 1, best + 1)
        }
        if output.last != words.count - 1 { output.append(words.count - 1) }
        return Array(Set(output)).sorted()
    }

    private static func isAmbiguous(words: [SpeechWordTimestamp], localBoundaries: [Int]) -> Bool {
        guard words.count >= 6, localBoundaries.count >= 2 else { return false }
        for boundary in localBoundaries.dropLast() where boundary + 1 < words.count {
            let token = words[boundary].text
            let gap = max(0, words[boundary + 1].startSeconds - words[boundary].endSeconds)
            let hasMeaningfulPunctuation = token.last.map { ".!?…。！？؟۔।॥,;:，、；：—–،؛".contains($0) } ?? false
            if !hasMeaningfulPunctuation && gap < 0.34 { return true }
        }
        return false
    }

    private static func splitOversizedBlock(_ words: [SpeechWordTimestamp]) -> [[SpeechWordTimestamp]] {
        guard words.count > maximumWordsPerBlock else { return [words] }
        var output: [[SpeechWordTimestamp]] = []
        var remaining = words
        while remaining.count > maximumWordsPerBlock {
            let lower = max(1, maximumWordsPerBlock - 24)
            let upper = maximumWordsPerBlock - 1
            var bestEnd = upper
            var bestScore = -Double.infinity
            for end in lower...upper {
                let gap = max(0, remaining[end + 1].startSeconds - remaining[end].endSeconds)
                let token = remaining[end].text
                let sentence = token.last.map { ".!?…。！？؟۔।॥".contains($0) } ?? false
                let clause = token.last.map { ",;:，、；：—–،؛".contains($0) } ?? false
                let score = gap * 100 + (sentence ? 60 : 0) + (clause ? 24 : 0) + Double(end - lower) * 0.05
                if score > bestScore {
                    bestScore = score
                    bestEnd = end
                }
            }
            output.append(Array(remaining[0...bestEnd]))
            remaining.removeFirst(bestEnd + 1)
        }
        if !remaining.isEmpty { output.append(remaining) }
        return output
    }
}
