import Foundation

public struct OnlineDefinition: Codable, Hashable, Sendable {
    public struct Meaning: Codable, Hashable, Sendable {
        public let partOfSpeech: String
        public let text: String
        public init(partOfSpeech: String = "", text: String) { self.partOfSpeech = partOfSpeech; self.text = text }
    }
    public struct WebTranslation: Codable, Hashable, Sendable {
        public let phrase: String
        public let translations: [String]
        public init(phrase: String, translations: [String]) { self.phrase = phrase; self.translations = translations }
    }
    public struct Example: Codable, Hashable, Sendable {
        public let sentence: String
        public let translation: String
        public init(sentence: String, translation: String) { self.sentence = sentence; self.translation = translation }
    }

    public let ukPhonetic: String
    public let usPhonetic: String
    public let ukAudioURL: URL?
    public let usAudioURL: URL?
    public let audioURL: URL?
    public let meanings: [Meaning]
    public let webTranslations: [WebTranslation]
    public let examples: [Example]
    public let allowsContentPersistence: Bool

    public init(ukPhonetic: String = "", usPhonetic: String = "", ukAudioURL: URL? = nil, usAudioURL: URL? = nil,
                audioURL: URL? = nil, meanings: [Meaning], webTranslations: [WebTranslation] = [],
                examples: [Example] = [], allowsContentPersistence: Bool = true) {
        self.ukPhonetic = ukPhonetic; self.usPhonetic = usPhonetic
        self.ukAudioURL = ukAudioURL; self.usAudioURL = usAudioURL; self.audioURL = audioURL
        self.meanings = meanings; self.webTranslations = webTranslations; self.examples = examples
        self.allowsContentPersistence = allowsContentPersistence
    }
}
