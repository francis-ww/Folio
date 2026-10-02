import Foundation

public enum MDictError: Error, LocalizedError, FolioMessageProviding, Sendable, Equatable {
    case malformed(String)
    case unsupported(String)
    case limitExceeded
    case missingDictionary
    case passcodeRequired

    public var errorDescription: String? { message.englishDescription }

    public var message: FolioMessage {
        switch self {
        case .malformed(let detail): FolioMessage("This dictionary is damaged or invalid: %@.", [.message(.archiveDetail(detail))])
        case .unsupported(let detail): FolioMessage("This dictionary uses %@, which Folio does not support yet.", [.message(.archiveDetail(detail))])
        case .limitExceeded: FolioMessage("This archive exceeds Folio’s import limits.")
        case .missingDictionary: FolioMessage("Import the matching MDX dictionary before adding its MDD resources.")
        case .passcodeRequired: FolioMessage("This dictionary requires an external registration code and user passcode that cannot be derived from the archive. Folio cannot import it without those credentials.")
        }
    }
}
