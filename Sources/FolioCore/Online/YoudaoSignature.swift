import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum YoudaoSignature {
    /// OpenAPI v3 uses the query unchanged up to 20 Unicode code points, otherwise
    /// its first ten + decimal code-point length + last ten, before URL encoding.
    public static func input(_ query: String) -> String {
        let characters = Array(query.unicodeScalars)
        guard characters.count > 20 else { return query }
        return String(String.UnicodeScalarView(characters.prefix(10))) + String(characters.count)
            + String(String.UnicodeScalarView(characters.suffix(10)))
    }

    public static func generate(appKey: String, query: String, salt: String, curtime: String, appSecret: String) -> String {
        let raw = appKey + input(query) + salt + curtime + appSecret
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
