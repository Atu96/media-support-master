import Foundation

struct WhisperTimestampTranscript: Sendable {
    let language: String
    let segments: [SRTSegment]
    let tokens: [SpeechWordTimestamp]
}

enum WhisperTimestampDecoder {
    private struct Offsets: Decodable { let from: Double; let to: Double }
    private struct Token: Decodable { let text: String; let id: Int; let offsets: Offsets }
    private struct Segment: Decodable { let text: String; let offsets: Offsets; let tokens: [Token]? }
    private struct Result: Decodable { let language: String }
    private struct Document: Decodable { let result: Result; let transcription: [Segment] }

    static func decode(_ data: Data) throws -> WhisperTimestampTranscript {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        var segments: [SRTSegment] = [], words: [SpeechWordTimestamp] = []
        var fullTiming = true
        for (index,segment) in doc.transcription.enumerated() {
            let start=segment.offsets.from/1000, end=segment.offsets.to/1000
            guard start.isFinite, end.isFinite, start >= 0, end > start else { throw NativeScriptAlignmentError.insufficientEvidence }
            segments.append(SRTSegment(id:index+1,index:index+1,timing:SRTTimecode.makeTiming(start:start,end:end),
                                       startSeconds:start,endSeconds:end,text:segment.text.trimmingCharacters(in:.whitespacesAndNewlines)))
            let tokens = (segment.tokens ?? []).filter { $0.id < 50257 && !$0.text.isEmpty }
            let text = tokens.map(\.text).joined().trimmingCharacters(in:.whitespacesAndNewlines)
            if text != segment.text.trimmingCharacters(in:.whitespacesAndNewlines) || text.contains("\u{fffd}") { fullTiming = false }
            for token in tokens {
                let s=token.offsets.from/1000, e=token.offsets.to/1000
                if !s.isFinite || !e.isFinite || s < start-0.1 || e > end+0.1 || e < s { fullTiming=false; continue }
                words.append(SpeechWordTimestamp(text:token.text,startSeconds:s,endSeconds:e))
            }
        }
        guard !segments.isEmpty else { throw NativeScriptAlignmentError.insufficientEvidence }
        if !zip(words,words.dropFirst()).allSatisfy({ $0.startSeconds <= $1.startSeconds }) { fullTiming=false }
        return WhisperTimestampTranscript(language:doc.result.language,segments:segments,tokens:fullTiming ? words : [])
    }

    static func language(from log: String) throws -> (code:String, confidence:Double) {
        let regex = try NSRegularExpression(pattern:#"auto-detected language:\s*([a-z]{2,3})\s*\(p\s*=\s*([0-9.]+)\)"#)
        guard let match=regex.firstMatch(in:log,range:NSRange(log.startIndex...,in:log)),
              let c=Range(match.range(at:1),in:log),let p=Range(match.range(at:2),in:log),
              let confidence=Double(log[p]),confidence.isFinite, confidence >= 0.5,confidence <= 1 else {
            throw NativeScriptAlignmentError.insufficientEvidence
        }
        return (String(log[c]),confidence)
    }
}
