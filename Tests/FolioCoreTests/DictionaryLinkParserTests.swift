import Foundation
import Testing
@testable import FolioCore

struct DictionaryLinkParserTests {
    @Test func recognizesSupportedSchemes() {
        #expect(DictionaryLinkParser.isEntryLink(URL(string: "entry://Money")!))
        #expect(DictionaryLinkParser.isEntryLink(URL(string: "bphrase://take%20up")!))
        #expect(DictionaryLinkParser.isEntryLink(URL(string: "bword://hello")!))
        #expect(DictionaryLinkParser.isEntryLink(URL(string: "ENTRY://Money")!))
        #expect(DictionaryLinkParser.isEntryLink(URL(string: "BPHRASE://take%20up")!))

        #expect(!DictionaryLinkParser.isEntryLink(URL(string: "https://example.com")!))
        #expect(!DictionaryLinkParser.isEntryLink(URL(string: "sound://word.wav")!))
        #expect(!DictionaryLinkParser.isEntryLink(URL(string: "folio-resource://sample/image.png")!))
    }

    @Test func extractsSimpleHeadword() {
        let url = URL(string: "entry://Money")!
        #expect(DictionaryLinkParser.extractTarget(from: url) == "Money")
    }

    @Test func extractsWithMultipleSlashes() {
        let url = URL(string: "entry:///Money")!
        #expect(DictionaryLinkParser.extractTarget(from: url) == "Money")
    }

    @Test func extractsPercentEncodedPhrase() {
        let url = URL(string: "bphrase://take%20care%20of")!
        #expect(DictionaryLinkParser.extractTarget(from: url) == "take care of")
    }

    @Test func decodesHTMLEntities() {
        let url = URL(string: "entry://&amp;c.")!
        #expect(DictionaryLinkParser.extractTarget(from: url) == "&c.")

        let url2 = URL(string: "entry://%26amp%3Bc.")!
        #expect(DictionaryLinkParser.extractTarget(from: url2) == "&c.")

        let url3 = URL(string: "entry://vis-%C3%A0-vis")!
        #expect(DictionaryLinkParser.extractTarget(from: url3) == "vis-à-vis")
    }

    @Test func stripsFragmentAndQueryParameters() {
        let url1 = URL(string: "entry://Money#origin_1")!
        #expect(DictionaryLinkParser.extractTarget(from: url1) == "Money")

        let url2 = URL(string: "entry://Money?highlight=true#origin_1")!
        #expect(DictionaryLinkParser.extractTarget(from: url2) == "Money")

        let url3 = URL(string: "bphrase://look%20up#examples")!
        #expect(DictionaryLinkParser.extractTarget(from: url3) == "look up")
    }

    @Test func handlesTrailingSlashesAndEmptyTargets() {
        let url1 = URL(string: "entry://hello/")!
        #expect(DictionaryLinkParser.extractTarget(from: url1) == "hello")

        let url2 = URL(string: "entry://")!
        #expect(DictionaryLinkParser.extractTarget(from: url2) == "")

        let url3 = URL(string: "entry:///")!
        #expect(DictionaryLinkParser.extractTarget(from: url3) == "")
    }
}
