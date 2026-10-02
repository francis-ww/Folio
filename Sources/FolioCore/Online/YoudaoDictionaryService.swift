import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DictionaryHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let retryAfter: String?
    public init(data: Data, statusCode: Int, retryAfter: String? = nil) {
        self.data = data; self.statusCode = statusCode; self.retryAfter = retryAfter
    }
}

public protocol DictionaryHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> DictionaryHTTPResponse
}

public struct URLSessionDictionaryHTTPClient: DictionaryHTTPClient {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }
    public func send(_ request: URLRequest) async throws -> DictionaryHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YoudaoError.invalidResponse }
        return .init(data: data, statusCode: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}

public actor YoudaoDictionaryService: OnlineDictionaryService {
    private let settings: any OnlineDictionarySettingsStore
    private let client: any DictionaryHTTPClient
    private let now: @Sendable () -> Date
    private let salt: @Sendable () -> String
    private var retryUntil: Date?
    private var lastConfiguration: YoudaoConfiguration?

    public init(settings: any OnlineDictionarySettingsStore, client: any DictionaryHTTPClient = URLSessionDictionaryHTTPClient(),
                now: @escaping @Sendable () -> Date = { .now }, salt: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.settings = settings; self.client = client; self.now = now; self.salt = salt
    }

    public func lookup(_ word: String) async throws -> DictionaryEntry? {
        try Task.checkCancellation()
        let query = String(word.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { return nil }
        let config = try await settings.configuration()
        guard let credentials = config.credentials, credentials.isValid else { throw YoudaoError.credentialsRequired }
        if lastConfiguration != config { retryUntil = nil; lastConfiguration = config }
        if let retryUntil, retryUntil > now() {
            throw YoudaoError.rateLimited(retryAfter: Int(ceil(retryUntil.timeIntervalSince(now()))))
        }
        let request = Self.makeRequest(query: query, credentials: credentials, api: config.api,
                                       salt: salt(), date: now())
        do {
            let response = try await client.send(request)
            try Task.checkCancellation()
            if response.statusCode == 429 {
                let delay = Self.retryDelay(response.retryAfter, now: now())
                throw YoudaoError.rateLimited(retryAfter: delay)
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                if response.statusCode == 401 || response.statusCode == 403 { throw YoudaoError.invalidCredentials }
                throw YoudaoError.server(response.statusCode)
            }
            return try YoudaoResponseDecoder.entry(from: response.data, requestedWord: query, api: config.api)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw YoudaoError.offline
            case .timedOut: throw YoudaoError.timedOut
            default: throw YoudaoError.network
            }
        } catch let error as YoudaoError {
            if case .rateLimited(let delay) = error, lastConfiguration == config {
                retryUntil = max(retryUntil ?? now(), now().addingTimeInterval(Double(delay ?? 5)))
            }
            throw error
        } catch { throw YoudaoError.network }
    }

    static func makeRequest(query: String, credentials: YoudaoCredentials, api: YoudaoAPI, salt: String, date: Date) -> URLRequest {
        let curtime = String(Int64(date.timeIntervalSince1970))
        var fields = ["q": query, "appKey": credentials.appKey, "salt": salt, "curtime": curtime, "signType": "v3",
                      "sign": YoudaoSignature.generate(appKey: credentials.appKey, query: query, salt: salt,
                                                       curtime: curtime, appSecret: credentials.appSecret)]
        if api == .translation { fields["from"] = "en"; fields["to"] = "zh-CHS" }
        else { fields["langType"] = "en"; fields["dicts"] = "ec"; fields["docType"] = "json" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let form = fields.sorted { $0.key < $1.key }.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
        var request = URLRequest(url: api.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(form.utf8)
        return request
    }

    private static func retryDelay(_ value: String?, now: Date) -> Int {
        if let value, let seconds = Int(value) { return min(3_600, max(1, seconds)) }
        if let value {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) { return min(3_600, max(1, Int(ceil(date.timeIntervalSince(now))))) }
        }
        return 5
    }
}
