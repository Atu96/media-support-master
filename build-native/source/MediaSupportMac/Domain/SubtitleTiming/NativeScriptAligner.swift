import Foundation
import NaturalLanguage

enum NativeScriptAlignmentError: LocalizedError {
    case insufficientEvidence
    case tooLarge
    var errorDescription: String? {
        switch self {
        case .insufficientEvidence: "Chưa đủ mốc lời nói để khớp chính xác. Kiểm tra ngôn ngữ và nội dung kịch bản."
        case .tooLarge: "Kịch bản quá dài cho một lượt khớp. Hãy chia thành các phần ngắn hơn."
        }
    }
}

/// Bounded-memory LCS maps original script units onto real Whisper token spans.
/// It never invents times for unmatched text or rewrites the script.
enum NativeScriptAligner {
    static func normalized(_ text: String) -> [Character] {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .filter { $0.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }.map { $0 }
    }
    static func align(script: String, tokens: [SpeechWordTimestamp], language: String) throws -> [SpeechWordTimestamp] {
        let a=normalized(script)
        var b:[Character]=[], times:[SpeechWordTimestamp]=[]
        for token in tokens {
            guard token.startSeconds.isFinite,token.endSeconds.isFinite, token.startSeconds >= 0,
                  token.endSeconds >= token.startSeconds else { throw NativeScriptAlignmentError.insufficientEvidence }
            for char in normalized(token.text) { b.append(char); times.append(token) }
        }
        let n=a.count,m=b.count
        guard n > 0,m > 0 else { throw NativeScriptAlignmentError.insufficientEvidence }
        guard n <= 200000,m <= 200000 else { throw NativeScriptAlignmentError.tooLarge }
        var mapping=[Int](repeating:-1,count:n)
        if a == b {
            mapping=Array(0..<n) // Common case: no quadratic work for a long exact transcript.
        } else {
        let band=max(abs(n-m)+16,min(512,max(n,m)/20+32)),width=2*band+1
        guard n*width <= 60_000_000 else { throw NativeScriptAlignmentError.tooLarge }
        var directions=[UInt8](repeating:0,count:(n*width+3)/4)
        let unreachable=Int32.min/4
        var previous=[Int32](repeating:0,count:m+2), current=previous
        if band+1 <= m { previous[band+1]=unreachable }
        for i in 1...n {
            try Task.checkCancellation()
            let lower=max(1,i-band),upper=min(m,i+band)
            current[lower-1]=lower==1 ? 0 : unreachable
            if upper+1 <= m { current[upper+1]=unreachable }
            for j in lower...upper {
                let direction:UInt8
                if a[i-1] == b[j-1] { current[j]=previous[j-1]+1;direction=1 }
                else if previous[j] >= current[j-1] { current[j]=previous[j];direction=2 }
                else { current[j]=current[j-1];direction=3 }
                let cell=(i-1)*width+j-(i-band)
                directions[cell/4] |= direction << ((cell%4)*2)
            }
            swap(&previous,&current)
        }
        guard Double(previous[m])/Double(n) >= 0.88 else { throw NativeScriptAlignmentError.insufficientEvidence }
        var i=n,j=m
        while i>0 && j>0 {
            let cell=(i-1)*width+j-(i-band)
            let d=(directions[cell/4] >> ((cell%4)*2)) & 3
            if d==1 { mapping[i-1]=j-1;i-=1;j-=1 }
            else if d==2 { i-=1 } else { j-=1 }
        }
        }
        let tokenizer=NLTokenizer(unit:.word)
        tokenizer.setLanguage(NLLanguage(rawValue:language));tokenizer.string=script
        let ranges=tokenizer.tokens(for:script.startIndex..<script.endIndex).filter { !normalized(String(script[$0])).isEmpty }
        guard !ranges.isEmpty else { throw NativeScriptAlignmentError.insufficientEvidence }
        var result:[SpeechWordTimestamp]=[],offset=0
        for (index,range) in ranges.enumerated() {
            try Task.checkCancellation()
            let lower=index==0 ? script.startIndex : range.lowerBound
            let upper=index+1 < ranges.count ? ranges[index+1].lowerBound : script.endIndex
            let text=String(script[lower..<upper]),count=normalized(text).count
            let unitStart=offset
            let mapped=mapping[offset..<min(n,offset+count)].filter { $0 >= 0 }
            offset += count
            guard count > 0,Double(mapped.count)/Double(count) >= 0.5,
                  let first=mapped.first,let last=mapped.last else { throw NativeScriptAlignmentError.insufficientEvidence }
            var timingLower=first,timingUpper=last
            // A small ASR substitution can use adjacent verified token spans.
            // No evenly spaced character timestamps are invented.
            if mapped.count<count {
                if unitStart>0,mapping[unitStart-1]>=0 {
                    let candidate=mapping[unitStart-1]+1
                    if first-candidate<=count { timingLower=min(first,candidate) }
                }
                if offset<n,mapping[offset]>=0 {
                    let candidate=mapping[offset]-1
                    if candidate-last<=count { timingUpper=max(last,candidate) }
                }
            }
            let start=times[timingLower].startSeconds,end=times[timingUpper].endSeconds
            guard end>start,end-start<=8 else { throw NativeScriptAlignmentError.insufficientEvidence }
            result.append(SpeechWordTimestamp(text:text,startSeconds:start,endSeconds:end))
        }
        guard offset == n else { throw NativeScriptAlignmentError.insufficientEvidence }
        return result
    }
}
