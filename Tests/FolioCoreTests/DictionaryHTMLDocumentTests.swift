import Foundation
import Testing
@testable import FolioCore

struct DictionaryHTMLDocumentTests {
    @Test func darkDocumentOverridesLegacyPaintAndPreservesContentAndSecurity() {
        let html = "<style>.entry { background-color: white !important; color: black; font-weight: bold }</style><p style='background: #fff !important; color: #000 !important; font-size: 20px'>汉字 &amp; meaning</p><img src='image.png'><a href='sound://voice.wav'>Audio</a>"
        let document = DictionaryHTMLDocument.make(html: html, baseURL: URL(string: "folio-resource://sample/")!, dark: true, fontSize: 25)
        #expect(document.contains("#1C1C1E") && document.contains("#E5E5EA"))
        #expect(!document.contains("background-color: white") && !document.contains("color: #000"))
        #expect(document.contains("font-weight: bold") && document.contains("font-size: 20px"))
        #expect(document.contains("汉字 &amp; meaning") && document.contains("src='image.png'"))
        #expect(document.contains("folio-resource://sample/voice.wav"))
        #expect(document.contains("script-src 'none'") && document.contains("connect-src 'none'"))
    }
    @Test func cssNormalizationPreservesURLsQuotedTextAndTypography() {
        let css = #".entry {background:url('a;color:red.png') #fff !important; /* legacy colour */ color:black!important; padding:10px; content:'color:red; background:white';} @media screen {p {background-color:white; font-style:italic}}"#
        let dark = DictionaryHTMLDocument.normalizeCSS(css, dark: true)
        #expect(dark.contains("url('a;color:red.png')") && dark.contains("content:'color:red; background:white'"))
        #expect(dark.contains("padding:10px") && dark.contains("font-style:italic"))
        #expect(!dark.contains("color:black") && !dark.contains("background-color:white"))
        #expect(DictionaryHTMLDocument.normalizeCSS(css, dark: false) == css)
    }
    @Test func lightModePreservesOriginalPaintAndNonFiniteFontSizesAreBounded() {
        let html = "<p style='color:black;background:white'>word</p>"
        let document = DictionaryHTMLDocument.make(html: html, baseURL: URL(string: "folio-resource://sample/")!, dark: false, fontSize: .nan)
        #expect(document.contains(html))
        #expect(document.contains("17.0px") && !document.contains("nanpx"))
        #expect(document.contains("color-scheme: light"))
    }
}
