import Foundation

public enum MDictError: Error, LocalizedError, Sendable {
    case malformed(String)
    case unsupported(String)
    case limitExceeded
    case missingDictionary

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): "This dictionary is damaged or invalid: \(detail)."
        case .unsupported(let detail): "This dictionary uses \(detail), which Folio does not support yet."
        case .limitExceeded: "This archive exceeds Folio’s import limits."
        case .missingDictionary: "Import the matching MDX dictionary before adding its MDD resources."
        }
    }
}
