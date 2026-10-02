# Folio

An English dictionary and vocabulary app for iOS 17+, written in Swift 6 with strict concurrency. Folio includes concurrent multi-dictionary lookup, offline MDX dictionaries, Youdao English–Chinese definitions, the iOS system dictionary sheet, pronunciation, saved vocabulary, FSRS practice, and bilingual settings with saved light/dark appearance.

## Build an IPA from Windows

Push this project to GitHub, then run **Build unsigned IPA** under **Actions**. The `macos-15` workflow builds a Release iPhone app with signing disabled and uploads `unsigned.ipa` in the **folio-unsigned-ipa** artifact. Sideloadly signs and installs the downloaded IPA on your iPhone. No Apple signing credentials are needed in GitHub.

Follow the [Windows build and sideloading guide](docs/WINDOWS_SIDELOADING.md) for the initial Git upload, manual build trigger, artifact download, Sideloadly setup, and keeping vocabulary data across updates.

## Run on a Mac

1. Open `Folio.xcodeproj` in Xcode 16 or later. Swift Package Manager resolves the pinned GRDB 7.0.0 dependency.
2. Select the **Folio** scheme and an iOS 17+ simulator, then run.
3. For a physical device, select your signing team and change the bundle identifier if needed.

The app starts with eight original sample definitions and an empty vocabulary collection. Save a word in **Search**, then open **Review**. Previews use isolated mock repositories with three due cards.

## App language

Choose **Library → Language** to follow the system, use English, or use Simplified Chinese. The interface updates immediately and remembers your choice. Chinese tabs read **查词 / 研习 / 生词本 / 文库**. Definitions keep their original language. See [localization and verification](docs/LOCALIZATION.md) for the central String Catalog, persistence, and layout checks.

## Import a dictionary

In **Library → Dictionary sources**, enable sources and tap **Reorder** to drag their priority. Word details offer source tabs and a system dictionary action. **Library → Appearance** selects System, Light, or Dark. See [dictionary sources and appearance](docs/MULTI_DICTIONARY_AND_APPEARANCE.md) for behavior and verification.

Open **Files → On My iPhone → Folio** and paste your `.mdx` and matching `.mdd` files directly into the folder, such as `Oxford.mdx` and `Oxford.mdd`. Folio scans automatically at launch and on foregrounding. **Library → Refresh Dictionaries** and pull-to-refresh scan manually; unchanged files are skipped. Each changed pair commits together, and a failed update preserves the previously indexed dictionary. See the [Files dictionary guide](docs/FILES_DICTIONARIES.md) for large-file handling, deletion, and verification.

Supported: MDict engine v2, including self-contained encrypted keyword indexes and fast/Salsa20/8 encrypted data blocks, UTF-8/UTF-16LE definitions, UTF-16LE resource keys, zlib and uncompressed blocks, cross-block records, shared record offsets, and `@@@LINK=` redirects. Images, CSS, fonts, and WAV/MP3 resources are served from SQLite through `folio-resource://`. Dictionary `entry://` and `bword://` links open definitions in the app. Audio playback still depends on iOS codec support.

Archives requiring an external registration code/passcode return `MDictError.passcodeRequired`. See [MDict encryption support](docs/MDICT_ENCRYPTION.md) for the exact v2 flag meanings, automatic key derivation, and fixture provenance.

Not yet supported: MDict v1/v3, registration-bound archives requiring external credentials, LZO, GB18030, embedded stylesheet substitutions, numbered MDD sets, script-dependent dictionary layouts, arbitrary external links, or optimized FSRS weights. Definitions disable JavaScript and external subresources. Import limits: one million keys, 100,000 blocks per section, 64 MiB per compressed/expanded block, 32 MiB per record, and 8 GiB total expanded record data. Large imports temporarily serialize dictionary lookups; the SwiftUI main actor remains free.

## Online English–Chinese lookup

Open **Library → Online Dictionary Settings**, enter your Youdao **App Key** and **App Secret**, select the enabled API for your account, and tap **Save keys**. Both fields are stored in the device Keychain. This repository includes no shared/default credentials; setup is required for live online requests. Youdao remains the default online provider.

Every enabled source participates concurrently, including Youdao when enabled. Results follow your saved priority; source failures appear separately and retain successful local results. Empty searches browse enabled local dictionaries without online requests. Disable Youdao or remove its saved keys in Library without changing imported dictionaries.

The default **Text API** provides Chinese translations and any additional fields included in the response. The optional **Dictionary API** requires separate activation and provides richer dictionary fields, including bilingual examples. Folio displays only returned data and plays available pronunciation URLs with AVPlayer. Network failures, missing credentials, account limits, and rate limits have actionable messages.

See [Youdao setup and implementation](docs/YOUDAO_ONLINE.md) for API differences, vocabulary behavior, signing, and verification.

## Architecture

`Sources/FolioCore` is a platform-independent Swift package. It contains Sendable domain values, repository protocols, the FSRS-6 scheduler, the bounded MDict reader, and an actor-owned GRDB/FTS5 library. `Sources/FolioArchive` provides zlib, RIPEMD-128, MDict fast decryption, and Salsa20/8 routines in portable C.

`Folio/Features` contains focused SwiftUI components and observable main-actor view models. Search uses debouncing and cancellation to suppress stale results. Review sessions reveal meanings before rating and advance only after a successful persistence write. Each session practices the currently due cards once; learning cards return after their next due time.

`Folio/Persistence` uses a SwiftData model actor, constructed away from the main actor. Card state and review history save together, with rollback on failure. `Folio/Rendering` keeps WebKit lifecycle callbacks on the main actor and reads resource bytes through the dictionary actor. A stopped scheme task receives no later callbacks.

`DictionaryLookupCoordinator` connects the local library to the actor-based `YoudaoDictionaryService`. `DictionaryEntry.online` stores structured meanings, accent-specific phonetics/audio, web translations, and bilingual examples without changing MDX HTML rendering or decoding older saved entries. CryptoKit computes OpenAPI SHA-256 signatures on Apple platforms; pinned Swift Crypto 3.9.0 supplies the same API for Linux/Windows core tests.

The design uses scalable Georgia headwords, semantic system text, warm neutral surfaces, adaptive dark mode, VoiceOver labels, spring motion that respects Reduce Motion, and subtle system haptics. Every reusable visual component has a mock-data preview.

## Verify

On macOS:

```sh
swift test
xcodebuild -project Folio.xcodeproj -scheme Folio \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Run native tests through Xcode's **Product → Test**. They cover SwiftData persistence across reopening, duplicate saves, review history, removal, persistence failure in the review flow, language persistence, compiled translations, and narrow layouts in both languages. GitHub Actions includes catalog validation, core tests, an iOS build, and native simulator tests.

Core fixtures compare 836 review transitions against the official **py-fsrs 6.3.2** implementation, with fuzzing disabled. Archive fixtures test compressed/uncompressed and encrypted records, checksums, corruption, truncation, unsupported versions, passcode errors, transaction rollback, cancellation, aliases, complete local PNG/WAV bytes, and literal FTS queries. Crypto tests compare RIPEMD-128, Salsa20/8, and fast decryption against independent Python vectors, including padding boundaries and counter carry/wrap. Synthetic fixture definitions are original content.

Youdao tests use original representative JSON fixtures, seven Python SHA-256 signature goldens, and injected mock HTTP clients. They cover both API envelopes, missing fields, pronunciation URLs, backward-compatible persistence, request encoding, credentials, cancellation, network errors, rate-limit cooldown, and local-first fallback. Tests never call Youdao or require developer keys.

The initial implementation was developed on Windows with Swift 6.0.3 under Ubuntu WSL. The core can be compiled and tested there. GRDB 7.0.0 assumes SQLite snapshot symbols, so Ubuntu testing requires a local SQLite build with FTS5 and `SQLITE_ENABLE_SNAPSHOT`; Apple's system SQLite supplies these APIs. The iOS UI and SwiftData tests still require a Mac; a Linux core test run does not verify them.

With Swift, a C compiler, Python 3, and SQLite/zlib development headers installed on Linux, run `bash Scripts/test_linux.sh`. This creates an isolated SQLite library in your cache. Set `FOLIO_SWIFT` to a toolchain executable if Swift is not on your PATH. `python3 Scripts/validate_project.py` checks project references and resource syntax; `--swiftc /path/to/swiftc` also parses the app sources without claiming Apple SDK typechecking.

Regenerate the Xcode project after adding/removing app files:

```sh
python3 Scripts/generate_project.py
```

Regenerate golden fixtures:

```sh
python3 -m pip install --target .tools/fsrs-reference fsrs==6.3.2
python3 Scripts/generate_fixtures.py --fsrs-path .tools/fsrs-reference
```

To regenerate only encryption fixtures and crypto vectors, run `python3 Scripts/generate_encryption_fixtures.py`. Both generators cache pinned, SHA-256-verified upstream Python references in ignored `.tools/mdict-reference`; first use requires network access. Running the Swift tests requires no Python or reference downloads.

`Scripts/generate_icon.py` recreates the geometric book icon using Pillow.

## Algorithm and format references

- [FSRS-6 equations](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
- [Official Python FSRS implementation](https://github.com/open-spaced-repetition/py-fsrs)
- [MDict format analysis](https://github.com/csarron/mdict-analysis)
- [GRDB](https://github.com/groue/GRDB.swift)
- [Apple's WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
