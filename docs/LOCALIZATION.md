# Folio in English and Simplified Chinese

Open **Library → Language** (**文库 → 语言**) and choose **System Default / 跟随系统**, **English**, or **简体中文**. Screens update immediately. The choice is saved on this device and restored on the next launch. Switching languages preserves the current query, navigation, collection, and review session.

The Chinese tabs are **查词**, **研习**, **生词本**, and **文库**. Dictionary definitions, examples, headwords, and imported dictionary names retain their original content. The interface includes translated labels, empty states, buttons, confirmations, accessibility text, import status, and actionable error messages.

## Implementation

- `Folio/Resources/Localizable.xcstrings` is the central String Catalog, with English as its source/development language and 225 translated entries in `en` and `zh-Hans`. Counts use English singular/plural forms and Chinese count wording.
- `AppLanguageManager` observes the choice and stores its raw value (`system`, `en`, `zh-Hans`) under `app_language` in UserDefaults. Previews use isolated managers without writing preferences.
- The bootstrap screen and `RootView` apply `.environment(\.locale, language.currentLocale)`. The view hierarchy keeps its identity when the language changes.
- System Default uses the first supported language in the device's preferred-language list. Simplified Chinese regional forms are supported; unsupported languages fall back to English. System-language changes are refreshed on locale notifications and when the app becomes active.
- SwiftUI literals and `LocalizedStringKey` parameters use the catalog directly. Runtime choice labels are explicitly localized, including rating titles and pronunciation accents.
- `FolioMessage` carries an untranslated format key and typed arguments through view models and background actors. `LocalizedMessageText` resolves them when displayed, so an existing status or error changes language too. Core errors keep English `LocalizedError` descriptions for non-UI callers; the app renders their message descriptors using its selected language.
- `AppLocalization` explicitly selects the corresponding compiled `.lproj` bundle for Foundation and UIKit text. Passing a locale only for number formatting would not reliably select the desired translation. It does not override `Bundle.main` or change `AppleLanguages`.
- Review intervals use locale-aware numbers and translated minutes, hours, and days. English dictionary headwords retain Georgia; Chinese editorial headers use the scalable system serif font and lighter letter spacing.

The catalog is included in the app resource build phase. The generated Xcode project declares both languages and enables string extraction. UIKit/WebKit accessibility text is updated when the selected locale changes. OS-owned interfaces, such as the Files app and keyboard, continue to follow the system's own language settings.

## Verification

Run from the repository root:

```sh
python3 Scripts/validate_project.py
swift test
```

On Linux with the project's isolated SQLite setup, use `bash Scripts/test_linux.sh` instead of `swift test`.

`validate_project.py` includes `validate_localization.py`, which checks both translations, completed string units, plural forms, format argument types/positions, and coverage of the app's localization call sites and MDict diagnostics. The audit excludes dictionary content, symbols, URLs, and preview fixture data. When adding a new wrapper around localized text, extend the audit's recognized APIs.

Core tests cover language resolution, deferred error arguments, English compatibility, and catalog coverage. Native `FolioTests` also cover:

- Preference persistence and invalid-preference fallback.
- Selection of English/Chinese from the compiled catalog, independently of system language.
- Nested translated errors, safe interpolation, and minute/hour/day intervals.
- Language changes with an existing error and an active review card.
- SwiftUI rendering differences and layouts at 320/375-point widths, in both languages, at standard and accessibility text sizes.

The GitHub **Swift and iOS checks** workflow validates resources, runs core tests, builds the app, and runs native tests on a simulator. On Windows/WSL, core tests, catalog checks, and Swift syntax can run; Apple SDK builds and simulator layout tests require that macOS workflow or a Mac. A passing source/layout-size check does not replace visual inspection for clipping.

For visual review on a simulator or iPhone:

1. Switch between all three options in Library. Confirm tabs, headings, buttons, and a previously visible status update immediately.
2. Open each tab at a narrow width and with a large accessibility text size. Verify captions wrap, the language menu remains usable, and review ratings fit in the two-column fallback.
3. Check an empty collection, no search results, online setup errors, and an invalid dictionary import. Confirm complete Chinese alerts and interpolated words/counts.
4. Reveal a review card, change the language, and return to Review. The same card and revealed meaning should remain.
5. Relaunch with an explicit language choice, then test System Default with English and Simplified Chinese device preferences.

See Apple's [String Catalog guide](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) and [SwiftUI localization guide](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization) when adding strings or plural variations.
