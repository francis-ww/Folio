import Foundation

/// Decodes both OpenAPI text responses and the dedicated ec dictionary envelope.
/// Optional data remains absent; the mapper never invents pronunciations or examples.
enum YoudaoResponseDecoder {
    static func entry(from data: Data, requestedWord: String, api: YoudaoAPI) throws -> DictionaryEntry? {
        guard data.count <= 2 * 1_024 * 1_024 else { throw YoudaoError.invalidResponse }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw YoudaoError.invalidResponse }
        guard response.errorCode.value == "0" else {
            if response.errorCode.value == "120" { return nil }
            throw YoudaoError.from(code: response.errorCode.value)
        }
        let body = response.result?.bodies.first ?? response.body
        let basic = body.basic
        var meanings = basic?.explains?.values ?? body.explains?.values ?? []
        if meanings.isEmpty { meanings = (response.translation ?? []).filter { !$0.isEmpty }.map { .init(text: $0) } }
        let web = (body.web ?? []).compactMap { value -> OnlineDefinition.WebTranslation? in
            let translations = value.value?.values ?? value.meaning?.values ?? []
            guard !translations.isEmpty else { return nil }
            return .init(phrase: value.key ?? value.phrase ?? requestedWord, translations: translations)
        }
        if meanings.isEmpty {
            meanings = web.filter { $0.phrase.caseInsensitiveCompare(requestedWord) == .orderedSame }
                .flatMap { $0.translations.map { OnlineDefinition.Meaning(text: $0) } }
        }
        guard !meanings.isEmpty else { return nil }
        let examples = (body.sentenceSample?.values ?? body.example?.values ?? []).compactMap { example -> OnlineDefinition.Example? in
            guard let sentence = example.sentence, !sentence.isEmpty, let translation = example.translation, !translation.isEmpty else { return nil }
            return .init(sentence: sentence, translation: translation)
        }
        let headword = response.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = headword.flatMap { $0.isEmpty ? nil : $0 } ?? requestedWord
        let online = OnlineDefinition(ukPhonetic: basic?.ukPhonetic ?? "", usPhonetic: basic?.usPhonetic ?? "",
                                      ukAudioURL: audioURL(basic?.ukSpeech), usAudioURL: audioURL(basic?.usSpeech),
                                      audioURL: audioURL(response.speakUrl), meanings: meanings, webTranslations: web,
                                      examples: examples, allowsContentPersistence: api != .dictionary)
        return DictionaryEntry(id: YoudaoEntryIdentity.id(for: word), dictionaryID: YoudaoEntryIdentity.dictionaryID,
                               headword: word, pronunciation: basic?.phonetic ?? basic?.ukPhonetic ?? basic?.usPhonetic ?? "",
                               partOfSpeech: meanings.first?.partOfSpeech ?? "", summary: meanings.map(\.text).joined(separator: "; "),
                               example: examples.first?.sentence ?? "", online: online)
    }

    static func audioURL(_ raw: String?) -> URL? {
        guard let raw, var components = URLComponents(string: raw), let host = components.host,
              components.user == nil, components.password == nil else { return nil }
        if components.scheme?.lowercased() == "http",
           host == "youdao.com" || host.hasSuffix(".youdao.com") || host == "ydstatic.com" || host.hasSuffix(".ydstatic.com") {
            components.scheme = "https"
        }
        guard components.scheme?.lowercased() == "https" else { return nil }
        return components.url
    }

    private struct Status: Decodable {
        let value: String
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) { value = string }
            else { value = String(try container.decode(Int.self)) }
        }
    }
    private struct Response: Decodable {
        let errorCode: Status
        let query: String?
        let translation: [String]?
        let speakUrl: String?
        let result: Results?
        let body: Body
        enum CodingKeys: String, CodingKey { case errorCode, query, translation, speakUrl, result }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            errorCode = try c.decode(Status.self, forKey: .errorCode)
            query = try c.decodeIfPresent(String.self, forKey: .query)
            translation = try c.decodeIfPresent([String].self, forKey: .translation)
            speakUrl = try c.decodeIfPresent(String.self, forKey: .speakUrl)
            result = try c.decodeIfPresent(Results.self, forKey: .result)
            body = try Body(from: decoder)
        }
    }
    private struct Results: Decodable {
        let bodies: [Body]
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            let results = try (try? c.decode([Result].self)) ?? [c.decode(Result.self)]
            bodies = results.map { $0.ec ?? $0.body }
        }
    }
    private struct Result: Decodable {
        let ec: Body?
        let body: Body
        enum CodingKeys: String, CodingKey { case ec }
        init(from decoder: any Decoder) throws {
            ec = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Body.self, forKey: .ec)
            body = try Body(from: decoder)
        }
    }
    private struct Body: Decodable {
        let basic: Basic?
        let explains: Explains?
        let web: [Web]?
        let sentenceSample: Examples?
        let example: Examples?
    }
    private struct Basic: Decodable {
        let phonetic: String?
        let ukPhonetic: String?
        let usPhonetic: String?
        let ukSpeech: String?
        let usSpeech: String?
        let explains: Explains?
        enum CodingKeys: String, CodingKey {
            case phonetic, ukPhonetic, usPhonetic, ukSpeech, usSpeech, explains
            case legacyUKPhonetic = "uk-phonetic", legacyUSPhonetic = "us-phonetic"
            case legacyUKSpeech = "uk-speech", legacyUSSpeech = "us-speech"
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            phonetic = try c.decodeIfPresent(String.self, forKey: .phonetic)
            ukPhonetic = try c.decodeIfPresent(String.self, forKey: .ukPhonetic) ?? c.decodeIfPresent(String.self, forKey: .legacyUKPhonetic)
            usPhonetic = try c.decodeIfPresent(String.self, forKey: .usPhonetic) ?? c.decodeIfPresent(String.self, forKey: .legacyUSPhonetic)
            ukSpeech = try c.decodeIfPresent(String.self, forKey: .ukSpeech) ?? c.decodeIfPresent(String.self, forKey: .legacyUKSpeech)
            usSpeech = try c.decodeIfPresent(String.self, forKey: .usSpeech) ?? c.decodeIfPresent(String.self, forKey: .legacyUSSpeech)
            explains = try c.decodeIfPresent(Explains.self, forKey: .explains)
        }
    }
    private struct Texts: Decodable {
        let values: [String]
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            values = try (try? c.decode([String].self)) ?? [c.decode(String.self)]
        }
    }
    private struct Web: Decodable {
        let key: String?
        let value: Texts?
        let phrase: String?
        let meaning: Texts?
    }
    private struct Example: Decodable { let sentence: String?; let translation: String? }
    private struct Examples: Decodable {
        let values: [Example]
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let array = try? c.decode([Example].self) { values = array }
            else if let example = try? c.decode(Example.self) { values = [example] }
            else if (try? c.decode(String.self)) != nil { values = [] } // No bilingual pair to display.
            else { throw YoudaoError.invalidResponse }
        }
    }
    private struct Explanation: Decodable { let text: String?; let pos: String?; let explain: Texts }
    private struct Explains: Decodable {
        let values: [OnlineDefinition.Meaning]
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let strings = try? c.decode([String].self) { values = strings.filter { !$0.isEmpty }.map(Self.meaning) }
            else if let string = try? c.decode(String.self) { values = string.isEmpty ? [] : [Self.meaning(string)] }
            else {
                values = try c.decode([Explanation].self).flatMap { explanation in
                    explanation.explain.values.filter { !$0.isEmpty }.map { text in
                        let value = Self.meaning(text)
                        return .init(partOfSpeech: explanation.pos ?? Self.partOfSpeech(explanation.text ?? "") ?? value.partOfSpeech,
                                     text: value.text)
                    }
                }
            }
        }
        static func partOfSpeech(_ raw: String) -> String? {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["n.", "v.", "vt.", "vi.", "adj.", "adv.", "pron.", "prep.", "conj.", "interj.", "num.", "det.", "aux.", "art."].contains(value) ? value : nil
        }
        static func meaning(_ raw: String) -> OnlineDefinition.Meaning {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dot = text.firstIndex(of: "."), let pos = partOfSpeech(String(text[...dot])) {
                return .init(partOfSpeech: pos, text: String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .init(text: text)
        }
    }
}

enum YoudaoEntryIdentity {
    static let dictionaryID = "youdao-online"
    static func id(for word: String) -> String {
        dictionaryID + ":" + (word.lowercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word.lowercased())
    }
    static func word(from id: String) -> String? {
        let prefix = dictionaryID + ":"
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count)).removingPercentEncoding
    }
}
