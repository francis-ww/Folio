import Foundation

public enum YoudaoAPI: String, Codable, CaseIterable, Hashable, Sendable {
    case translation
    case dictionary

    public var title: String { self == .translation ? "Text API" : "Dictionary API" }
    var endpoint: URL {
        // These are fixed HTTPS endpoints; credentials never become URL parameters.
        URL(string: self == .translation ? "https://openapi.youdao.com/api" : "https://openapi.youdao.com/v2/dict")!
    }
}

public struct YoudaoCredentials: Codable, Sendable, Equatable {
    public let appKey: String
    public let appSecret: String
    public init(appKey: String, appSecret: String) { self.appKey = appKey; self.appSecret = appSecret }
    public var isValid: Bool { !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appSecret.isEmpty }
}

public struct YoudaoConfiguration: Codable, Sendable, Equatable {
    public let credentials: YoudaoCredentials?
    public let api: YoudaoAPI
    public init(credentials: YoudaoCredentials? = nil, api: YoudaoAPI = .translation) {
        self.credentials = credentials; self.api = api
    }
}

public protocol OnlineDictionarySettingsStore: Sendable {
    func configuration() async throws -> YoudaoConfiguration
    func update(_ configuration: YoudaoConfiguration) async throws
}

/// Preview/test configuration. Live credentials use the app's Keychain actor.
public actor MemoryOnlineDictionarySettings: OnlineDictionarySettingsStore {
    private var value: YoudaoConfiguration
    public init(_ value: YoudaoConfiguration = .init()) { self.value = value }
    public func configuration() -> YoudaoConfiguration { value }
    public func update(_ configuration: YoudaoConfiguration) { value = configuration }
}

public protocol OnlineDictionaryService: Sendable {
    func lookup(_ word: String) async throws -> DictionaryEntry?
}
