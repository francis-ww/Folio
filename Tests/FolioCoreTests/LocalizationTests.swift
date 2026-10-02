import Foundation
import Testing
@testable import FolioCore

struct LocalizationTests {
    @Test func languagePreferencesResolveSupportedSystemLanguages() {
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hans-HK", "en-HK"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR", "zh_CN"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB", "zh-Hans"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW", "en"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: []) == "en")
        #expect(AppLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]) == "en")
        #expect(AppLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en"]) == "zh-Hans")
        #expect(AppLanguage(rawValue: "unsupported") == nil)
    }

    @Test func deferredMessagesKeepArgumentsAndEnglishCompatibility() {
        let error = MDictError.unsupported("UTF-32 text encoding")
        #expect(error.message.arguments == [.message(FolioMessage("%@ text encoding", [.text("UTF-32")]))])
        #expect(error.localizedDescription == "This dictionary uses UTF-32 text encoding, which Folio does not support yet.")
        #expect(MDictError.unsupported("the .zip file type").message.arguments == [.message(FolioMessage("the .%@ file type", [.text("zip")]))])
        #expect(MDictError.unsupported("block encryption method 15").message.arguments == [.message(FolioMessage("block encryption method %lld", [.integer(15)]))])
        #expect(YoudaoError.rateLimited(retryAfter: 5).message.arguments == [.integer(5)])
        #expect(YoudaoError.api("104").message.arguments == [.text("104")])
        #expect(FolioMessage.from(YoudaoError.offline, fallback: "Unused fallback").key == YoudaoError.offline.message.key)
        // Unknown OS errors use app-owned copy rather than freezing the OS language
        // or displaying raw database paths and other internal implementation data.
        #expect(FolioMessage.from(URLError(.unknown), fallback: "Try again").key == "Try again")
        #expect(FolioMessage("No definition was found for %@.", [.text("100% curious")]).englishDescription == "No definition was found for 100% curious.")
    }

    private func catalog() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Folio/Resources/Localizable.xcstrings"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func centralCatalogIncludesBothLanguagesAndNaturalPluralForms() throws {
        let catalog = try catalog()
        #expect(catalog["sourceLanguage"] as? String == "en")
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(strings.count >= 190)
        for (key, value) in strings {
            let languages = try #require(value["localizations"] as? [String: [String: Any]])
            for language in ["en", "zh-Hans"] {
                let localization = try #require(languages[language], "Missing \(language): \(key)")
                if let unit = localization["stringUnit"] as? [String: String] {
                    #expect(unit["state"] == "translated")
                    #expect(unit["value"]?.isEmpty == false)
                } else {
                    let variations = try #require(localization["variations"] as? [String: [String: Any]])
                    #expect(variations["plural"]?["other"] != nil)
                    if language == "en" { #expect(variations["plural"]?["one"] != nil) }
                }
            }
        }
        for error in [YoudaoError.credentialsRequired, .invalidCredentials, .serviceNotEnabled, .offline, .timedOut,
                      .invalidResponse, .accountLimit, .rateLimited(retryAfter: nil), .rateLimited(retryAfter: 1),
                      .rateLimited(retryAfter: 5), .server(503), .api("104"), .network] {
            #expect(strings[error.message.key] != nil)
        }
        for error in [MDictError.malformed("truncated file"), .unsupported("LZO compression"), .limitExceeded, .missingDictionary, .passcodeRequired] {
            #expect(strings[error.message.key] != nil)
        }
    }
}
