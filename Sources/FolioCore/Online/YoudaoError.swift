import Foundation

public enum YoudaoError: Error, LocalizedError, FolioMessageProviding, Sendable, Equatable {
    case credentialsRequired, invalidCredentials, serviceNotEnabled, offline, timedOut, invalidResponse, accountLimit
    case rateLimited(retryAfter: Int?)
    case server(Int)
    case api(String)
    case network

    public var errorDescription: String? { message.englishDescription }

    public var message: FolioMessage {
        switch self {
        case .credentialsRequired: FolioMessage("Add your Youdao App Key and App Secret in Library → Online Dictionary Settings to look up this word online.")
        case .invalidCredentials: FolioMessage("Youdao could not verify your keys. Check your App Key and App Secret in Library.")
        case .serviceNotEnabled: FolioMessage("Enable the selected Youdao API for your application. Dictionary API access needs separate activation.")
        case .offline: FolioMessage("You’re offline. Your installed dictionaries are still available. Connect to look up this word with Youdao.")
        case .timedOut: FolioMessage("Youdao took a little too long to respond. Please try again.")
        case .invalidResponse: FolioMessage("Youdao returned a response Folio couldn’t read. Please try again.")
        case .accountLimit: FolioMessage("Your Youdao account has reached its balance or usage limit. Check your account before trying again.")
        case .rateLimited(let seconds): seconds.map {
            FolioMessage($0 == 1 ? "Youdao is receiving too many requests. Try again in %lld second." : "Youdao is receiving too many requests. Try again in %lld seconds.", [.integer($0)])
        } ?? FolioMessage("Youdao is receiving too many requests. Please wait a moment and try again.")
        case .server: FolioMessage("Youdao is temporarily unavailable. Please try again shortly.")
        case .api(let code): FolioMessage("Youdao couldn’t complete this lookup (code %@). Check your service configuration and try again.", [.text(code)])
        case .network: FolioMessage("Couldn’t reach Youdao. Check your connection and try again.")
        }
    }

    static func from(code: String) -> Self {
        switch code {
        case "108", "111", "202": .invalidCredentials
        case "110", "104", "205", "390001": .serviceNotEnabled
        case "401": .accountLimit
        case "411", "412": .rateLimited(retryAfter: nil)
        default: .api(code)
        }
    }
}
