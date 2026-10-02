# Folio

An offline English dictionary and vocabulary app for iOS 17+, written in Swift 6 with strict concurrency. The first version includes dictionary search, native and HTML definitions, pronunciation, saved vocabulary, FSRS practice, and a dictionary import library.

## Build an IPA from Windows

Push this project to GitHub, then run **Build unsigned IPA** under **Actions**. The `macos-15` workflow builds a Release iPhone app with signing disabled and uploads `unsigned.ipa` in the **folio-unsigned-ipa** artifact. Sideloadly signs and installs the downloaded IPA on your iPhone. No Apple signing credentials are needed in GitHub.

Follow the [Windows build and sideloading guide](docs/WINDOWS_SIDELOADING.md) for the initial Git upload, manual build trigger, artifact download, Sideloadly setup, and keeping vocabulary data across updates.

## Run on a Mac

1. Open `Folio.xcodeproj` in Xcode 16 or later. Swift Package Manager resolves the pinned GRDB 7.0.0 dependency.
2. Select the **Folio** scheme and an iOS 17+ simulator, then run.
3. For a physical device, select your signing team and change the bundle identifier if needed.

The app starts with eight original sample definitions and an empty vocabulary collection. Save a word in **Discover**, then open **Practice**. Previews use isolated mock repositories with three due cards.

## Import a dictionary

In **Library**, select your `.mdx` and `.mdd` files together. Matching files must share a filename stem, such as `Oxford.mdx` and `Oxford.mdd`. An MDD can also be added after its matching dictionary. Selected imports commit together; failures or cancellation roll back the entire batch. Reimporting an MDX replaces that dictionary and its resources. Saved cards retain definition snapshots.

Supported: unencrypted MDict engine v2, UTF-8/UTF-16LE definitions, UTF-16LE resource keys, zlib and uncompressed blocks, cross-block records, shared record offsets, and `@@@LINK=` redirects. Images, CSS, fonts, and WAV/MP3 resources are served from SQLite through `folio-resource://`. Dictionary `entry://` and `bword://` links open definitions in the app. Audio playback still depends on iOS codec support.

Not yet supported: MDict v1/v3, encrypted archives, LZO, GB18030, embedded stylesheet substitutions, numbered MDD sets, script-dependent dictionary layouts, arbitrary external links, or optimized FSRS weights. Definitions disable JavaScript and external subresources. Import limits: one million keys, 100,000 blocks per section, 64 MiB per compressed/expanded block, 32 MiB per record, and 8 GiB total expanded record data. Large imports temporarily serialize dictionary lookups; the SwiftUI main actor remains free.

## Architecture

`Sources/FolioCore` is a platform-independent Swift package. It contains Sendable domain values, repository protocols, the FSRS-6 scheduler, the bounded MDict reader, and an actor-owned GRDB/FTS5 library. `Sources/FolioArchive` provides a small zlib bridge.

`Folio/Features` contains focused SwiftUI components and observable main-actor view models. Search uses debouncing and cancellation to suppress stale results. Review sessions reveal meanings before rating and advance only after a successful persistence write. Each session practices the currently due cards once; learning cards return after their next due time.

`Folio/Persistence` uses a SwiftData model actor, constructed away from the main actor. Card state and review history save together, with rollback on failure. `Folio/Rendering` keeps WebKit lifecycle callbacks on the main actor and reads resource bytes through the dictionary actor. A stopped scheme task receives no later callbacks.

The design uses scalable Georgia headwords, semantic system text, warm neutral surfaces, adaptive dark mode, VoiceOver labels, spring motion that respects Reduce Motion, and subtle system haptics. Every reusable visual component has a mock-data preview.

## Verify

On macOS:

```sh
swift test
xcodebuild -project Folio.xcodeproj -scheme Folio \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Run native tests through Xcode's **Product → Test**. They cover SwiftData persistence across reopening, duplicate saves, review history, removal, and persistence failure in the review flow. GitHub Actions includes core tests, an iOS build, and native simulator tests.

Core fixtures compare 836 review transitions against the official **py-fsrs 6.3.2** implementation, with fuzzing disabled. Archive fixtures test compressed/uncompressed records, checksums, corruption, truncation, unsupported versions/encryption, transaction rollback, cancellation, aliases, local PNG/WAV bytes, and literal FTS queries. Synthetic fixture definitions are original content.

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

`Scripts/generate_icon.py` recreates the geometric book icon using Pillow.

## Algorithm and format references

- [FSRS-6 equations](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
- [Official Python FSRS implementation](https://github.com/open-spaced-repetition/py-fsrs)
- [MDict format analysis](https://github.com/csarron/mdict-analysis)
- [GRDB](https://github.com/groue/GRDB.swift)
- [Apple's WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
