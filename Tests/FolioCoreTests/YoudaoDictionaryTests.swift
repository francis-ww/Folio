import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FolioCore

struct YoudaoDictionaryTests {
    private let credentials = YoudaoCredentials(appKey: "test-app-key", appSecret: "test-app-secret")

    private func fixture(_ name: String, ext: String = "json") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func signaturesMatchIndependentPythonGoldens() throws {
        struct Vector: Decodable { let query: String; let input: String; let appKey: String; let salt: String; let curtime: String; let appSecret: String; let sign: String }
        struct Reference: Decodable { let cases: [Vector] }
        let vectors = try JSONDecoder().decode(Reference.self, from: fixture("youdao-signatures")).cases
        #expect(vectors.count == 7)
        for vector in vectors {
            #expect(YoudaoSignature.input(vector.query) == vector.input)
            #expect(YoudaoSignature.generate(appKey: vector.appKey, query: vector.query, salt: vector.salt,
                                            curtime: vector.curtime, appSecret: vector.appSecret) == vector.sign)
        }
    }

    @Test func decodesTextBasicPhoneticsAndWebMeanings() throws {
        let entry = try #require(try YoudaoResponseDecoder.entry(from: fixture("youdao-text"), requestedWord: "ephemeral", api: .translation))
        let online = try #require(entry.online)
        #expect(entry.headword == "ephemeral")
        #expect(entry.html.isEmpty)
        #expect(entry.pronunciation == "ɪˈfem.ər.əl")
        #expect(online.ukPhonetic == "ɪˈfem.ər.əl")
        #expect(online.usPhonetic == "ɪˈfem.ɚ.əl")
        #expect(online.ukAudioURL?.absoluteString.contains("type=1") == true)
        #expect(online.usAudioURL?.absoluteString.contains("type=2") == true)
        #expect(online.meanings == [.init(partOfSpeech: "adj.", text: "短暂的；转瞬即逝的"), .init(partOfSpeech: "n.", text: "短暂存在的事物")])
        #expect(online.webTranslations.first?.translations == ["短暂的美丽"])
        #expect(online.examples.isEmpty)
        #expect(online.allowsContentPersistence)
    }

    @Test func decodesDictionaryEnvelopeAndBilingualExamples() throws {
        let entry = try #require(try YoudaoResponseDecoder.entry(from: fixture("youdao-dictionary"), requestedWord: "ephemeral", api: .dictionary))
        let online = try #require(entry.online)
        #expect(entry.headword == "ephemeral")
        #expect(online.meanings.first?.partOfSpeech == "adj.")
        #expect(online.meanings.first?.text == "短暂的；转瞬即逝的")
        #expect(online.ukAudioURL?.scheme == "https")
        #expect(online.examples.first?.sentence == "The garden held the ephemeral beauty of the first snow.")
        #expect(online.examples.first?.translation == "花园留住了初雪转瞬即逝的美。")
        #expect(online.webTranslations.first?.phrase == "ephemeral beauty")
        #expect(!online.allowsContentPersistence)
        let bookmark = entry.vocabularySnapshot
        #expect(bookmark.id == entry.id && bookmark.headword == entry.headword)
        #expect(bookmark.online == nil && bookmark.html.isEmpty && bookmark.example.isEmpty)
        #expect(!bookmark.summary.contains("短暂"))
    }

    @Test func sparseTranslationAndUnknownWordsAreHandled() throws {
        let data = Data(#"{"errorCode":0,"query":"bloom","translation":["开花"],"speakUrl":"https://openapi.youdao.com/audio.mp3"}"#.utf8)
        let entry = try #require(try YoudaoResponseDecoder.entry(from: data, requestedWord: "bloom", api: .translation))
        #expect(entry.summary == "开花")
        #expect(entry.online?.examples.isEmpty == true)
        #expect(entry.online?.ukAudioURL == nil && entry.online?.usAudioURL == nil)
        #expect(entry.online?.audioURL?.scheme == "https")
        #expect(try YoudaoResponseDecoder.entry(from: Data(#"{"errorCode":"120"}"#.utf8), requestedWord: "unknown", api: .dictionary) == nil)
        #expect(throws: YoudaoError.invalidResponse) {
            try YoudaoResponseDecoder.entry(from: Data("not json".utf8), requestedWord: "bloom", api: .translation)
        }
    }

    @Test func unsafeAudioLinksAreIgnored() {
        for raw in ["javascript:alert(1)", "file:///tmp/audio.wav", "http://example.com/audio", "https://user:password@example.com/audio"] {
            #expect(YoudaoResponseDecoder.audioURL(raw) == nil)
        }
        #expect(YoudaoResponseDecoder.audioURL("http://dict.youdao.com/audio")?.scheme == "https")
        #expect(YoudaoResponseDecoder.audioURL("https://cdn.example.com/audio") != nil)
    }

    @Test func oldStoredEntriesAndOnlineSnapshotsRoundTrip() throws {
        let legacy = Data(#"{"id":"old","dictionaryID":"local","headword":"bloom","pronunciation":"","partOfSpeech":"","summary":"A flower.","example":"","html":"<p>A flower.</p>"}"#.utf8)
        let entry = try JSONDecoder().decode(DictionaryEntry.self, from: legacy)
        #expect(entry.online == nil && entry.html == "<p>A flower.</p>")
        let online = try #require(try YoudaoResponseDecoder.entry(from: fixture("youdao-text"), requestedWord: "ephemeral", api: .translation))
        let restored = try JSONDecoder().decode(DictionaryEntry.self, from: JSONEncoder().encode(online.vocabularySnapshot))
        #expect(restored.online == online.online)
        #expect(restored.summary == online.summary)
        #expect(restored.id == online.id)
    }

    @Test(arguments: [YoudaoAPI.translation, .dictionary])
    func sendsSignedUTF8PostWithoutExposingSecret(_ api: YoudaoAPI) async throws {
        let client = MockDictionaryHTTPClient(.response(.init(data: try fixture("youdao-text"), statusCode: 200)))
        let settings = MemoryOnlineDictionarySettings(.init(credentials: credentials, api: api))
        let service = YoudaoDictionaryService(settings: settings, client: client,
                                             now: { Date(timeIntervalSince1970: 1_700_000_000) }, salt: { "fixed-salt-001" })
        _ = try await service.lookup("a+b & 汉字")
        let request = try #require(await client.requests.first)
        let fields = try form(request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.query == nil)
        #expect(fields["q"] == "a+b & 汉字")
        #expect(fields["signType"] == "v3" && fields["curtime"] == "1700000000")
        #expect(fields["sign"] == YoudaoSignature.generate(appKey: credentials.appKey, query: "a+b & 汉字", salt: "fixed-salt-001",
                                                            curtime: "1700000000", appSecret: credentials.appSecret))
        #expect(fields["appSecret"] == nil)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!body.contains(credentials.appSecret))
        if api == .translation {
            #expect(request.url?.path == "/api" && fields["from"] == "en" && fields["to"] == "zh-CHS")
        } else { #expect(request.url?.path == "/v2/dict" && fields["langType"] == "en" && fields["dicts"] == "ec") }
    }

    @Test func missingKeysAndEmptyQueriesNeverReachNetwork() async throws {
        let client = MockDictionaryHTTPClient(.response(.init(data: Data(), statusCode: 200)))
        let service = YoudaoDictionaryService(settings: MemoryOnlineDictionarySettings(), client: client)
        #expect(try await service.lookup("   ") == nil)
        await #expect(throws: YoudaoError.credentialsRequired) { try await service.lookup("bloom") }
        #expect(await client.requests.isEmpty)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost])
    func reportsNetworkFailures(_ code: URLError.Code) async throws {
        let client = MockDictionaryHTTPClient(.network(code))
        let service = YoudaoDictionaryService(settings: MemoryOnlineDictionarySettings(.init(credentials: credentials)), client: client)
        let expected: YoudaoError = code == .timedOut ? .timedOut : (code == .cannotFindHost ? .network : .offline)
        await #expect(throws: expected) { try await service.lookup("bloom") }
    }

    @Test func HTTPRateLimitHonorsCooldown() async throws {
        let client = MockDictionaryHTTPClient(.response(.init(data: Data(), statusCode: 429, retryAfter: "12")))
        let service = YoudaoDictionaryService(settings: MemoryOnlineDictionarySettings(.init(credentials: credentials)), client: client,
                                             now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await #expect(throws: YoudaoError.rateLimited(retryAfter: 12)) { try await service.lookup("bloom") }
        await #expect(throws: YoudaoError.rateLimited(retryAfter: 12)) { try await service.lookup("bloom") }
        #expect(await client.requests.count == 1)
    }

    @Test(arguments: ["108", "110", "202", "401", "411", "412"])
    func mapsAPIErrors(_ code: String) async throws {
        let client = MockDictionaryHTTPClient(.response(.init(data: Data("{\"errorCode\":\"\(code)\"}".utf8), statusCode: 200)))
        let service = YoudaoDictionaryService(settings: MemoryOnlineDictionarySettings(.init(credentials: credentials)), client: client)
        await #expect(throws: YoudaoError.from(code: code)) { try await service.lookup("bloom") }
    }

    @Test func changingKeysClearsOldCooldownAndUsesNewConfiguration() async throws {
        let client = MockDictionaryHTTPClient(.response(.init(data: Data(), statusCode: 429, retryAfter: "30")))
        let settings = MemoryOnlineDictionarySettings(.init(credentials: credentials))
        let service = YoudaoDictionaryService(settings: settings, client: client,
                                             now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await #expect(throws: YoudaoError.rateLimited(retryAfter: 30)) { try await service.lookup("ephemeral") }
        await settings.update(.init(credentials: .init(appKey: "new-app-key", appSecret: "new-app-secret")))
        await client.setBehavior(.response(.init(data: try fixture("youdao-text"), statusCode: 200)))
        #expect(try await service.lookup("ephemeral")?.online != nil)
        #expect(await client.requests.count == 2)
        let request = try #require(await client.requests.last)
        #expect(try form(request)["appKey"] == "new-app-key")
        await settings.update(.init())
        await #expect(throws: YoudaoError.credentialsRequired) { try await service.lookup("ephemeral") }
        #expect(await client.requests.count == 2)
    }

    @Test func cancellationIsNotReportedAsNetworkFailure() async throws {
        let client = MockDictionaryHTTPClient(.network(.cancelled))
        let service = YoudaoDictionaryService(settings: MemoryOnlineDictionarySettings(.init(credentials: credentials)), client: client)
        await #expect(throws: CancellationError.self) { try await service.lookup("bloom") }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.lookup("bloom")
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await client.requests.count == 1)
    }

    private func form(_ request: URLRequest) throws -> [String: String] {
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        return try Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { field in
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]), try #require(String(parts[1]).removingPercentEncoding))
        })
    }
}

private actor MockDictionaryHTTPClient: DictionaryHTTPClient {
    enum Behavior: Sendable { case response(DictionaryHTTPResponse); case network(URLError.Code) }
    private var behavior: Behavior
    private(set) var requests: [URLRequest] = []
    init(_ behavior: Behavior) { self.behavior = behavior }
    func setBehavior(_ behavior: Behavior) { self.behavior = behavior }
    func send(_ request: URLRequest) throws -> DictionaryHTTPResponse {
        requests.append(request)
        switch behavior {
        case .response(let response): return response
        case .network(let code): throw URLError(code)
        }
    }
}
