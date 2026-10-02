import Foundation

/// An untranslated message. Keeping the key and arguments lets an existing alert
/// follow a language change without repeating its underlying operation.
public struct FolioMessage: Sendable, Equatable, Hashable {
    public indirect enum Argument: Sendable, Equatable, Hashable {
        case text(String)
        case integer(Int)
        case message(FolioMessage)
    }

    public let key: String
    public let arguments: [Argument]

    public init(_ key: String, _ arguments: [Argument] = []) {
        self.key = key
        self.arguments = arguments
    }

    public var englishDescription: String {
        String(format: key, locale: Locale(identifier: "en"), arguments: arguments.map {
            switch $0 {
            case .text(let value): value as CVarArg
            case .integer(let value): Int64(value) as CVarArg
            case .message(let value): value.englishDescription as CVarArg
            }
        })
    }

    public static func from(_ error: any Error, fallback: String) -> Self {
        (error as? any FolioMessageProviding)?.message ?? Self(fallback)
    }

    /// Parser diagnostics are localized too; format arguments remain archive data.
    public static func archiveDetail(_ detail: String) -> Self {
        if detail.hasSuffix(" text encoding") {
            return Self("%@ text encoding", [.text(String(detail.dropLast(14)))])
        }
        if detail.hasPrefix("the ."), detail.hasSuffix(" file type") {
            return Self("the .%@ file type", [.text(String(detail.dropFirst(5).dropLast(10)))])
        }
        if detail.hasPrefix("block encryption method "), let number = Int(detail.dropFirst(24)) {
            return Self("block encryption method %lld", [.integer(number)])
        }
        return Self(detail)
    }
}

public protocol FolioMessageProviding: Error, Sendable {
    var message: FolioMessage { get }
}
