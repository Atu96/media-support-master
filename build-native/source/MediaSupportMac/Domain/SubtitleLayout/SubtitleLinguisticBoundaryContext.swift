import Foundation
import NaturalLanguage

/// Phân tích cả đoạn một lần, không phụ thuộc dấu câu. Chỉ chấm điểm boundary;
/// không sửa chữ, không tải assets, không giữ tagger dùng chung giữa các thread.
struct SubtitleLinguisticBoundaryContext: Sendable {
    let lexicalOffsets: Set<Int>
    let costs: [Int: Double]

    private struct Token {
        let start: Int
        let end: Int
        let key: String
        let tag: NLTag?
    }

    static func isJapanese(languageCode: String, text: String) -> Bool {
        let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init) ?? ""
        return code == "ja" || code == "jp"
            || text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    init(text: String, languageCode: String) {
        guard !Self.isJapanese(languageCode: languageCode, text: text), !Task.isCancelled else {
            lexicalOffsets = []; costs = [:]; return
        }
        let requested = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
        var code = requested
            .split(separator: "-").first.map(String.init) ?? "auto"
        if code == "auto" || code.isEmpty {
            code = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "und"
        }
        if ["zh", "cmn", "yue"].contains(code) {
            code = requested.contains("hant") || requested.hasSuffix("-tw")
                || requested.hasSuffix("-hk") || code == "yue" ? "zh-Hant" : "zh-Hans"
        }
        let language = NLLanguage(rawValue: code)
        let offsets = Dictionary(uniqueKeysWithValues:
            (Array(text.indices) + [text.endIndex]).enumerated().map { ($0.element, $0.offset) })
        var tags: [Int: NLTag] = [:]
        // POS không khả dụng ở mọi ngôn ngữ. Khi thiếu, vẫn dùng tokenizer và
        // profile nhỏ bên dưới; tuyệt đối không requestAssets/tải model thêm.
        if NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass) {
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = text
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                guard !Task.isCancelled else { return false }
                if let tag, let offset = offsets[range.lowerBound] { tags[offset] = tag }
                return true
            }
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language)
        var tokens: [Token] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            guard !Task.isCancelled else { return false }
            if let start = offsets[range.lowerBound], let end = offsets[range.upperBound] {
                tokens.append(Token(start: start, end: end, key: text[range].lowercased(), tag: tags[start]))
            }
            return true
        }
        let characterCount = offsets.count - 1
        lexicalOffsets = Set(tokens.flatMap { [$0.start, $0.end] }.filter { $0 > 0 && $0 < characterCount })
        let profile = Self.profiles[code] ?? (code.hasPrefix("zh") ? Self.profiles["zh-Hans"]
            : Self.profiles[code.split(separator: "-").first.map(String.init) ?? code])
        var scored: [Int: Double] = [:]
        for (left, right) in zip(tokens, tokens.dropFirst()) {
            var cost = 0.0
            if profile?.forward.contains(left.key) == true { cost += 90 }
            if profile?.backward.contains(right.key) == true { cost += 100 }
            if profile?.clauseStarts.contains(right.key) == true { cost -= 52 }
            if profile?.clauseStarts.contains(left.key) == true { cost += 78 }
            if Self.bondedPairs[code]?.contains(left.key + " " + right.key) == true { cost += 170 }
            if left.tag == .determiner || left.tag == .preposition { cost += 72 }
            if left.tag == .adjective, right.tag == .noun { cost += 65 }
            if left.tag == .adverb, right.tag == .verb || right.tag == .adjective { cost += 58 }
            if left.tag == .pronoun, right.tag == .verb { cost += 48 }
            if left.tag == .noun, right.tag == .verb { cost += 24 }
            if left.tag == .verb, right.tag == .verb { cost += 30 }
            if left.tag == .conjunction { cost += 55 }
            if right.tag == .conjunction { cost -= 32 }
            if right.tag == .preposition { cost -= 12 }
            // Trung không có whitespace. Boundary trong token từ có điểm phạt
            // riêng ở cost(at:); cụm 的/了/着/过 và classifier nên bám từ trước/sau.
            if code.hasPrefix("zh"), ["的", "了", "着", "过", "们", "著", "過", "們"].contains(right.key) { cost += 100 }
            if code.hasPrefix("zh"), left.tag == .classifier { cost += 85 }
            if code == "ko" {
                if ["에서", "에게", "으로", "에"].contains(where: { left.key.hasSuffix($0) }) { cost += 55 }
                if ["은", "는"].contains(where: { left.key.hasSuffix($0) }) { cost += 28 }
                if ["지만", "어서", "아서", "와서", "해서", "니까", "는데"].contains(where: { left.key.hasSuffix($0) }) { cost -= 35 }
            }
            for offset in left.end...max(left.end, right.start) { scored[offset] = cost }
        }
        costs = scored
    }

    func cost(at offset: Int) -> Double {
        if let cost = costs[offset] { return cost }
        // Tokenizer CJK/Thái/Indic có thể nhận một từ nhiều grapheme. Hạn chế
        // chẻ bên trong, nhưng vẫn cho phép fallback khi safe width quá hẹp.
        return lexicalOffsets.contains(offset) ? 0 : 85
    }

    private struct Profile {
        let forward: Set<String>
        let backward: Set<String>
        let clauseStarts: Set<String>

        init(_ forward: String, _ clauseStarts: String, backward: String = "") {
            self.forward = Set(forward.split(separator: " ").map(String.init))
            self.backward = Set(backward.split(separator: " ").map(String.init))
            self.clauseStarts = Set(clauseStarts.split(separator: " ").map(String.init))
        }
    }

    /// Supplemental function words cho ngôn ngữ không có POS trên macOS.
    /// Các ngôn ngữ khác vẫn đi qua tokenizer/POS nếu có, không bị ép rule Anh.
    private static let profiles: [String: Profile] = [
        "vi": Profile("các những mỗi một không chưa chẳng đang đã sẽ rất quá phải cần nên của với để bởi tại tôi bạn họ ta mình",
                      "nhưng vì nên nếu khi dù hoặc mà"),
        "en": Profile("a an the this that these those my your our their not can could should will would must has have i you he she we they",
                      "but because although unless if when while therefore however so"),
        "ko": Profile("이 그 저 한 모든 매우 너무 더 안 못 수 것 줄", "하지만 그러나 그래서 그러면 그런데 만약 그리고",
                      backward: "은 는 이 가 을 를 에 의 도 만 수 것 줄"),
        "zh-Hans": Profile("一个 这个 那个 每个 所有 很 非常 正在 将 不 没 没有 应该 可以 必须 一個 這個 那個 每個 將 沒 沒有 應該 必須",
                           "但是 不过 因为 所以 如果 虽然 然而 而且 因此 然后 不過 因為 雖然 然後 但係"),
        "fr": Profile("le la les un une des du de à en mon ma mes ce cette ces ne pas très je tu il elle nous vous ils elles on avons avez ont suis est sommes êtes sont",
                      "mais car parce lorsque quand puisque pourtant cependant donc"),
        "de": Profile("der die das ein eine einer eines dem den des im am zum zur nicht sehr ich du er sie es wir ihr habe hast hat haben habt bin bist ist sind seid",
                      "aber weil wenn obwohl während deshalb jedoch sondern"),
        "es": Profile("el la los las un una unos unas del al mi mis su sus muy no yo tú él ella nosotros nosotras vosotros ellos ellas",
                      "pero porque aunque cuando mientras entonces sino"),
        "pt": Profile("o a os as um uma uns umas do da dos das no na meu minha muito não eu tu ele ela nós vocês eles elas",
                      "mas porque embora quando enquanto porém portanto"),
        "it": Profile("il lo la i gli le un uno una del della nel nella molto non io tu lui lei noi voi loro",
                      "ma perché quando mentre sebbene quindi però"),
        "ru": Profile("в во на к ко с со из до для без не очень этот эта эти мы вы он она они я ты",
                      "но потому если когда хотя поэтому однако"),
        "uk": Profile("в у на до для без не дуже цей ця ці", "але бо якщо коли хоча тому однак"),
        "id": Profile("di ke dari untuk tidak belum akan sedang sangat sebuah setiap",
                      "tetapi namun karena sehingga jika ketika meskipun lalu"),
        "ms": Profile("di ke dari untuk tidak belum akan sedang sangat sebuah setiap",
                      "tetapi namun kerana jika apabila walaupun maka"),
        "tr": Profile("bir bu şu o her çok en değil", "ama fakat çünkü eğer ancak sonra"),
        "nl": Profile("de het een mijn jouw zijn haar deze dit niet heel", "maar omdat hoewel wanneer terwijl dus"),
        "pl": Profile("w na do dla bez nie bardzo ten ta te", "ale ponieważ jeśli kiedy chociaż jednak"),
        "ar": Profile("في من إلى على عن مع هذا هذه كل لا لم لن جدا", "لكن لأن إذا عندما بينما لذلك ولكن لكننا لكنهم لكنها لكنك لكنني ولكننا"),
        "hi": Profile("यह वह एक हर बहुत नहीं", "लेकिन क्योंकि अगर जब इसलिए जबकि"),
        "th": Profile("ไม่ กำลัง จะ ต้อง เรา", "แต่ เพราะ ดังนั้น ถ้า เมื่อ แม้ว่า แล้ว", backward: "มาก"),
        "sv": Profile("en ett den det de min din inte mycket", "men eftersom när medan därför"),
        "da": Profile("en et den det de min din ikke meget", "men fordi når mens derfor"),
        "no": Profile("en et den det de min din ikke veldig", "men fordi når mens derfor"),
        "fi": Profile("tämä tuo yksi jokainen hyvin ei", "mutta koska jos kun vaikka siksi"),
        "el": Profile("ο η το οι τα ένας μια ένα δεν πολύ εγώ εσύ εμείς εσείς", "αλλά επειδή όταν ενώ αν όμως"),
        "bn": Profile("এক এই সেই খুব না আমরা", "কিন্তু কারণ তাই যদি যখন যদিও"),
        "he": Profile("של עם את אל לא מאוד אני אנחנו אתה הוא היא", "אבל כי לכן אם כאשר למרות אולם ולכן ואם"),
    ]

    private static let bondedPairs: [String: Set<String>] = [
        "vi": ["chúng tôi", "chúng ta", "quyết định", "bởi vì", "cho nên", "tại vì", "do đó", "mặc dù", "tuy nhiên", "có lẽ", "đối với", "bao giờ"],
        "en": ["because of", "even though", "as well", "rather than", "in order", "so that"],
        "fr": ["parce que", "bien que", "tandis que", "afin de"],
        "es": ["ya que", "aunque sea", "sin embargo", "por eso"],
        "pt": ["por isso", "apesar de", "já que"],
        "it": ["anche se", "dato che", "per questo"],
        "ru": ["потому что", "так как", "для того"],
        "de": ["auch wenn", "so dass"],
    ]
}
