# Dictionary sources and appearance

In **Library → Dictionary sources** (**文库 → 词典来源**), use the switches to enable imported MDX dictionaries, Youdao, or the bundled sample dictionary. Tap **Reorder / 调整顺序** and drag the native handles to set priority. Changes apply immediately; enabled state and order survive relaunches. Disabling a source does not remove its files, saved words, or review history.

Every enabled source participates in a nonempty query. Youdao needs developer credentials as before; disable it to avoid online requests. Empty searches browse enabled local dictionaries without contacting Youdao. Newly imported dictionaries are enabled by default. Their settings remain independent of the language and appearance choices.

Search results include source labels and follow dictionary priority. Open a word to use the horizontal source tabs; each source retains its own definition, pronunciation, and renderer. MDX uses WebKit with local MDD resources, while Youdao uses native cards. Saving a word saves the selected source's definition, subject to the existing Youdao bookmark policy. Previously saved snapshots remain readable if a source is disabled or removed; removed MDD resources are no longer available.

The permanent **iOS System Dictionary / 系统词典** action opens Apple's reference interface as a sheet. It is enabled only when `dictionaryHasDefinition(forTerm:)` reports an available definition, and is checked again when the app becomes active. Availability depends on the dictionaries installed in iOS. System definitions are not copied, indexed, or saved into Folio. This uses Apple's [UIReferenceLibraryViewController](https://developer.apple.com/documentation/uikit/uireferencelibraryviewcontroller).

Choose **Library → Appearance** (**文库 → 外观**) for **System / 跟随系统**, **Light / 浅色**, or **Dark / 深色**. System removes the override. Explicit choices update the window and its sheets and persist under `app_appearance`.

## Implementation

`DictionarySelection` stores an ordered list and disabled source IDs. `UserDefaultsDictionarySelectionStore` owns the `dictionary_selection` preference on an actor and performs atomic read/modify/write operations. Library switches and reorder operations update the UI synchronously, then persist through an ordered queue. Successful writes invalidate search and detail lookups. Previews and tests use memory stores.

`DictionaryLookupCoordinator` captures a preference snapshot for each lookup and launches a throwing task group across enabled sources. Reports retain results and translated failures independently and restore configured priority after tasks finish. Cancellation propagates rather than becoming an error banner. Source-specific lookups never return another source's entry. SQLite searches filter by source before applying result limits, so another dictionary cannot consume its quota.

Local database reads remain serialized on the library actor; network tasks can overlap those reads and each other. MDX parsing and imports remain off the main actor. Word details can show their initial definition while aggregation completes. Results and source failures commit only for the current request; changing selection triggers a new lookup. No online definition cache was added.

The native palette uses dynamic neutral surfaces and semantic foreground colours; AccentColor also includes a dark variant. `preferredColorScheme` applies the saved appearance at the root. WebKit prepares HTML off the main actor and reloads for colour-scheme or text-size changes. Dark HTML uses charcoal `#1C1C1E` and muted text `#E5E5EA`, with readable links and borders. The document and MDD stylesheet handlers remove legacy foreground/background paint declarations, including `!important`, while keeping typography, spacing, and background image URLs. Bitmap image content is preserved. Author JavaScript and external subresources remain disabled by the existing content security policy.

## Verification

```sh
python3 Scripts/validate_project.py
swift test
```

On Linux/WSL, use `bash Scripts/test_linux.sh` for the isolated SQLite setup.

Core tests cover overlapping source queries, deterministic ordering, disabling every source, preference changes, persistence, concurrent toggles, partial failures, missing entries, cancellation, scoped FTS, and light/dark HTML and CSS. Existing archive, encryption, Youdao signature/decoding, FSRS, and localization coverage remains in the suite. Earlier fallback tests were updated for the requested simultaneous-query semantics.

Native simulator tests cover appearance persistence, immediate source settings, ordered persistence, saving the selected source, and narrow English/Chinese layouts in both appearances. The existing macOS GitHub workflow builds and runs these tests. Windows/WSL checks do not substitute for Apple SDK builds or visual inspection.

On an iPhone or simulator, verify:

1. Import two MDX files with a shared word, enable Youdao, and check all available definitions and their source order. Reorder, disable one source, and reopen the word.
2. Disable Youdao and confirm online setup/network errors disappear. Disconnect with Youdao enabled and confirm local definitions remain available with an online error shown separately.
3. Switch source tabs and save a definition. Confirm the Collection entry comes from that source. Relaunch to check source switches, priority, language, and appearance.
4. Check a word available in the system dictionary and an unknown term. Confirm only the available word opens the reference sheet.
5. Test legacy MDX files with white inline backgrounds and external stylesheets in dark mode. Check images, local audio, links, and large text. Switch back to light and System.
