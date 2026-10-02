import Foundation
import Testing
import GRDB
@testable import FolioCore

struct BrowseAndEntityDecodingTests {
    @Test func decodesNamedAndNumericHTMLEntities() {
        #expect(HTMLEntityDecoder.decode("&amp;c.") == "&c.")
        #expect(HTMLEntityDecoder.decode("&lt;hello&gt;") == "<hello>")
        #expect(HTMLEntityDecoder.decode("&quot;quoted&quot;") == "\"quoted\"")
        #expect(HTMLEntityDecoder.decode("&#39;bout") == "'bout")
        #expect(HTMLEntityDecoder.decode("&apos;apostrophe&apos;") == "'apostrophe'")
        #expect(HTMLEntityDecoder.decode("word&nbsp;word") == "word word")
        #expect(HTMLEntityDecoder.decode("&#38;") == "&")
        #expect(HTMLEntityDecoder.decode("&#x26;") == "&")
        #expect(HTMLEntityDecoder.decode("&#8212;") == "—")
        #expect(HTMLEntityDecoder.decode("&#x2014;") == "—")
        #expect(HTMLEntityDecoder.decode("caf&eacute;") == "café")
        #expect(HTMLEntityDecoder.decode("na&iuml;ve") == "naïve")
        #expect(HTMLEntityDecoder.decode("fa&ccedil;ade") == "façade")
        #expect(HTMLEntityDecoder.decode("plain text") == "plain text")
        #expect(HTMLEntityDecoder.decode("AT&T") == "AT&T")
        #expect(HTMLEntityDecoder.decode("&unknown;") == "&unknown;")
        #expect("&amp;c.".decodingHTMLEntities == "&c.")
    }

    @Test func escapesCommonCharacters() {
        #expect(HTMLEntityDecoder.escape("&c.") == "&amp;c.")
        #expect(HTMLEntityDecoder.escape("<tag>") == "&lt;tag&gt;")
        #expect(HTMLEntityDecoder.escape("\"quote\"") == "&quot;quote&quot;")
        #expect(HTMLEntityDecoder.escape("'apostrophe'") == "&#39;apostrophe&#39;")
        #expect(HTMLEntityDecoder.escape("plain") == "plain")
    }

    @Test func dictionaryEntryDecodesHeadwordUponInitAndJSONDecoding() throws {
        let entry = DictionaryEntry(id: "test-1", headword: "&amp;c.", summary: "And so forth.")
        #expect(entry.headword == "&c.")
        #expect(entry.displayHeadword == "&c.")

        let json = #"{"id":"legacy-1","dictionaryID":"folio-sample","headword":"&amp;c.","summary":"And so forth."}"#
        let decoded = try JSONDecoder().decode(DictionaryEntry.self, from: Data(json.utf8))
        #expect(decoded.headword == "&c.")
        #expect(decoded.displayHeadword == "&c.")
    }

    @Test func validatesBrowseFilterCriteria() {
        // Exclude symbols
        let symbolEntry = DictionaryEntry(id: "1", headword: "%", summary: "Percent sign")
        #expect(!symbolEntry.isValidForBrowse)

        // Exclude archaic abbreviations starting with &
        let ampEntry = DictionaryEntry(id: "2", headword: "&amp;c.", summary: "Et cetera")
        #expect(!ampEntry.isValidForBrowse)
        let ampDecoded = DictionaryEntry(id: "2b", headword: "&c.", summary: "Et cetera")
        #expect(!ampDecoded.isValidForBrowse)

        // Exclude affixes and suffixes
        let suffixHyphen = DictionaryEntry(id: "3", headword: "-aria", summary: "Suffix")
        #expect(!suffixHyphen.isValidForBrowse)
        let suffixApos = DictionaryEntry(id: "4", headword: "'-lit", summary: "Suffix")
        #expect(!suffixApos.isValidForBrowse)
        let prefixHyphen = DictionaryEntry(id: "5", headword: "electro-", summary: "Prefix")
        #expect(!prefixHyphen.isValidForBrowse)

        // Exclude numbers
        let numberEntry = DictionaryEntry(id: "6", headword: "123", summary: "Numbers")
        #expect(!numberEntry.isValidForBrowse)

        // Exclude redirect definitions
        let linkDef = DictionaryEntry(id: "7", headword: "graph", summary: "See chart", html: "@@@LINK=chart")
        #expect(!linkDef.isValidForBrowse)
        let seeDef = DictionaryEntry(id: "8", headword: "graph", summary: "See chart", html: "See chart")
        #expect(!seeDef.isValidForBrowse)
        let seeHeadword = DictionaryEntry(id: "9", headword: "See graph", summary: "Graph definition", html: "<p>Graph</p>")
        #expect(!seeHeadword.isValidForBrowse)

        // Accept valid English headwords
        let validAurora = DictionaryEntry(id: "10", headword: "aurora", summary: "Dawn light", html: "<p>Dawn light</p>")
        #expect(validAurora.isValidForBrowse)
        let validSerendipity = DictionaryEntry(id: "11", headword: "serendipity", summary: "Pleasant discovery", html: "<p>Discovery</p>")
        #expect(validSerendipity.isValidForBrowse)
    }

    @Test func browseQueryExcludesJunkAndRedirectRecordsAndSamplesValidHeadwords() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        let fixture = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        try await library.importArchives([fixture])
        let source = try #require(try await library.sources().first { !$0.isSample })

        // tiny.mdx contains: alias, aurora, bloom, redirect (@@@LINK=aurora)
        let browseResults = try await library.search("", dictionaryID: source.id)
        #expect(!browseResults.isEmpty)
        #expect(browseResults.allSatisfy { $0.isValidForBrowse })
        #expect(!browseResults.contains { $0.headword == "redirect" })
        #expect(browseResults.allSatisfy { $0.dictionaryID == source.id })
    }

    @Test func lookupHandlesBothDecodedAndLegacyEscapedHeadwords() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.withLibraryWrite { db in
            try db.execute(sql: "INSERT INTO sources(id, title, filename) VALUES ('custom', 'Custom', 'custom')")
            let entry = DictionaryEntry(id: "c1", dictionaryID: "custom", headword: "&amp;c.", summary: "And so forth.")
            // Manually insert with raw &amp;c. in headword column to simulate pre-existing index
            let data = try JSONEncoder().encode(entry)
            try db.execute(sql: "INSERT INTO entries(id, dictionaryID, headword, payload) VALUES (?, ?, ?, ?)",
                           arguments: ["c1", "custom", "&amp;c.", data])
        }

        let found = try await library.lookup("&c.", dictionaryID: "custom")
        #expect(found != nil)
        #expect(found?.headword == "&c.")
    }
}
