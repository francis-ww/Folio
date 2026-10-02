import Foundation
import SwiftUI
import Testing
import FolioCore
@testable import Folio

struct AppLocalizationTests {
    @Test @MainActor func languageChoicePersistsAndOverridesSystemPreference() throws {
        let suite = "Folio.LocalizationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = AppLanguageManager(defaults: defaults, preferredLanguages: ["zh-Hans-CN"])
        #expect(manager.selection == .system)
        #expect(manager.currentLocale.identifier == "zh-Hans")
        for choice in AppLanguage.allCases {
            manager.selection = choice
            let reopened = AppLanguageManager(defaults: defaults, preferredLanguages: ["zh-Hans-CN"])
            #expect(reopened.selection == choice)
            #expect(reopened.currentLocale.identifier == (choice == .english ? "en" : "zh-Hans"))
        }
        defaults.set("unknown", forKey: AppLanguageManager.preferenceKey)
        #expect(AppLanguageManager(defaults: defaults, preferredLanguages: ["en-US"]).selection == .system)
    }

    @Test func compiledCatalogSelectsLanguageIndependentlyOfSystem() {
        let message = FolioMessage("No definition was found for %@.", [.text("100% curious")])
        #expect(AppLocalization.string(message, locale: Locale(identifier: "en")) == "No definition was found for 100% curious.")
        #expect(AppLocalization.string(message, locale: Locale(identifier: "zh-Hans")) == "没有找到“100% curious”的释义。")
        let error = MDictError.unsupported("UTF-32 text encoding").message
        #expect(AppLocalization.string(error, locale: Locale(identifier: "zh-Hans")) == "这部词典使用了UTF-32 文本编码，Folio 暂不支持。")
        #expect(AppLocalization.string(FolioMessage("Library"), locale: Locale(identifier: "zh-Hans")) == "文库")
        #expect(AppLocalization.reviewInterval(90, locale: Locale(identifier: "en")) == "1.5 min")
        #expect(AppLocalization.reviewInterval(3_600, locale: Locale(identifier: "zh-Hans")) == "1 小时")
        #expect(AppLocalization.reviewInterval(86_400, locale: Locale(identifier: "zh-Hans")) == "1 天")
    }

    @Test @MainActor func existingMessagesRerenderWithoutChangingReviewState() async throws {
        let services = AppServices.preview()
        let review = ReviewViewModel(vocabulary: services.vocabulary)
        await review.begin()
        review.reveal()
        let cardID = try #require(review.current?.id)
        let error = YoudaoError.offline.message
        let english = AppLocalization.string(error, locale: services.language.currentLocale)
        services.language.selection = .simplifiedChinese
        let chinese = AppLocalization.string(error, locale: services.language.currentLocale)
        #expect(english != chinese)
        #expect(chinese.hasPrefix("当前没有网络连接。"))
        #expect(review.current?.id == cardID)
        #expect(review.isRevealed && review.completed == 0)

        // Exercise SwiftUI's locale environment and compiled plural variations,
        // rather than just checking the Foundation renderer above.
        func image(locale: Locale) throws -> Data {
            let content = VStack {
                Text("Library")
                Text("\(1) words worth returning to.")
                LocalizedMessageText(error)
            }.padding().frame(width: 320).environment(\.locale, locale)
            let renderer = ImageRenderer(content: content)
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try image(locale: Locale(identifier: "en")) != image(locale: Locale(identifier: "zh-Hans")))
    }

    @Test @MainActor func editorialComponentsWrapWithinNarrowLayouts() {
        for identifier in ["en", "zh-Hans"] {
            for typeSize in [DynamicTypeSize.large, .accessibility3] {
                for width: CGFloat in [320, 375] {
                    let language = AppLanguageManager(defaults: nil, initial: identifier == "en" ? .english : .simplifiedChinese)
                    let content = VStack(alignment: .leading, spacing: 24) {
                        EditorialHeader(eyebrow: "Always within reach", title: "Your reference\nshelf.", subtitle: "Bring your dictionaries. Explore them offline.")
                        LanguageSettingsView(manager: language)
                        OnlineDefinitionCardView(definition: SampleData.onlineEntry.online!)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                            ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                                RatingButton(rating: rating, interval: 90) {}
                            }
                        }
                        ReviewCompletionView(count: 1)
                    }.padding(24).environment(\.locale, Locale(identifier: identifier))
                        .environment(\.dynamicTypeSize, typeSize)
                    let controller = UIHostingController(rootView: content)
                    let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                    #expect(size.width <= width + 0.5)
                    #expect(size.height.isFinite && size.height > 0)
                    // Expanding vertically is essential for long translations and
                    // accessibility sizes; scroll views provide that space in-app.
                    let renderer = ImageRenderer(content: content.frame(width: width))
                    #expect(renderer.uiImage != nil)
                }
            }
        }
    }
}
