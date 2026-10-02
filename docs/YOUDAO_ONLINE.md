# Youdao online dictionary

## Setup

1. Obtain an App Key and App Secret from your [Youdao developer account](https://ai.youdao.com/).
2. Enable the API you intend to use for that application.
3. Open Folio's **Library → Online Dictionary Settings**.
4. Enter both keys, choose **Text API** or **Dictionary API**, and tap **Save keys**.
5. Enable Youdao in **Library → Dictionary sources**, then search in **Search**. Enabled sources are queried together; local and online definitions appear in your chosen order.

Youdao is the default online provider. No default developer keys or backend are supplied in this repository, so the initial indicator says **Setup required**. Once credentials are saved and the source is enabled, it shows **Youdao Online Active (Default)**; disabling the source shows **Disabled**. The indicator does not guarantee the account's balance or API entitlement. **Remove keys** deletes the Keychain item. Keychain failures remain visible and do not overwrite the UI's previous configured state.

## API selection

| Mode | Endpoint | Availability in Folio |
| --- | --- | --- |
| Text API, default | `https://openapi.youdao.com/api` | Chinese translations; additional basic/web fields when returned. Optional fields may be absent. |
| Dictionary API | `https://openapi.youdao.com/v2/dict` | Decodes the `result`/`ec` envelope, accent phonetics/audio, meanings, web translations, and bilingual example pairs. |

The [text API documentation](https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html) specifies `from=en` and `to=zh-CHS` for this direction. The [dictionary API documentation](https://ai.youdao.com/DOCSIRMA/html/dictionary/api/ydcd/index.html) specifies `langType=en`, `dicts=ec`, and separate activation. Dictionary API terms prohibit retaining returned content. Folio therefore saves only the user's headword as a bookmark in that mode, fetches its definition when opened, and offers **Look up this word** during practice. Text-mode entries and local definitions retain the existing vocabulary snapshot behavior. Missing examples and accent-specific pronunciation data are never synthesized. Audio availability also depends on the account's enabled services.

The checked-in JSON files are original test fixtures shaped around documented fields, including older text-API basic/web naming. They are not captured responses from a live account. Exact account-specific field availability needs verification with authorized credentials.

## Lookup and presentation

`DictionaryLookupCoordinator` implements `DictionaryRepository`, querying enabled sources concurrently and returning deterministic priority order with independent source failures. Empty searches browse enabled local entries without network traffic. Dictionary links and bookmarked online words also route through the coordinator; resources continue to come from the local repository. Disabling Youdao prevents its lookup requests. A network failure retains successful local definitions. See [multi-dictionary behavior](MULTI_DICTIONARY_AND_APPEARANCE.md).

`DictionaryEntry.online` is optional, preserving decoding of previously saved vocabulary and local entry JSON. It holds UK/US phonetics and audio URLs, generic pronunciation audio, part-of-speech meanings, web translations, bilingual examples, and a content-retention flag. MDX entries continue to use their existing HTML. Text-mode online snapshots can be reviewed offline; dedicated dictionary-mode bookmarks need a connection to retrieve meanings.

`OnlineDefinitionCardView` uses warm paper colors, numbered senses, generous spacing, and serif English examples. Text remains selectable. `OnlinePronunciationPlayer` uses AVPlayer with spoken-audio playback, observes loading/failure/completion, ignores stale callbacks, times out stalled loading, and stops when the definition disappears. Only HTTPS pronunciation URLs are played. Known Youdao HTTP audio links are upgraded to HTTPS; unsafe schemes are omitted. No global App Transport Security exception is added.

## Requests, credentials, and errors

The service uses asynchronous URLSession POST requests with UTF-8 form encoding and fixed HTTPS endpoints. It signs the raw query before URL encoding. OpenAPI v3 signature input is the query for up to twenty Unicode code points; longer input becomes its first ten code points, decimal code-point count, and last ten. The lowercase SHA-256 digest covers `appKey + input + salt + curtime + appSecret`. Each live request gets a new UUID salt and UTC epoch-seconds timestamp. Apple's CryptoKit is used on iOS/macOS; Swift Crypto provides the Linux/Windows implementation used by tests. Queries are bounded to 200 characters.

The App Secret is used only in signature calculation; it is never a request field or URL parameter. Keys and the selected API are saved together in a Keychain item accessible while this device is unlocked. Keychain calls run on their own actor. No secrets are checked into the repository, written to UserDefaults, or logged. A distributor wanting a shared, immediately active default should provide an authenticated backend with server-held credentials; the settings/service protocols allow substituting that integration.

URLSession uses an ephemeral configuration without a disk URL cache. The service and coordinator do not cache online result objects. Offline, timeout, authentication, unavailable service, account balance, HTTP errors, and API errors map to descriptive `YoudaoError` cases. HTTP 429 respects a bounded `Retry-After` cooldown (seconds or HTTP date); Youdao 411/412 applies a short cooldown. There is no automatic request retry that would consume additional quota. Cancellation remains cancellation and stale search tasks cannot replace newer UI results.

## Verification

Run `swift test` on macOS, or the documented WSL `Scripts/test_linux.sh` command. Core tests require no Youdao credentials or live network requests:

- JSON mapping for both response shapes and sparse translation-only results.
- Seven independent Python SHA-256 vectors, including truncation boundaries, Chinese text, emoji, and combining characters.
- Signed UTF-8 POST bodies, API-specific fields, and omission of the secret.
- Missing credentials, API errors, offline/timeouts, rate limiting, and cancellation.
- Installed MDX precedence, samples, no local matches, removing the last MDX, and bookmark lookup.
- Decoding old stored entries and snapshot/bookmark retention behavior.

Use the existing macOS GitHub Actions build to compile the native UI, AVPlayer, and Keychain integration against Apple's SDKs. Linux parsing does not verify those frameworks. Live entitlement, API response completeness, and audio playback still need a configured account and an iPhone/simulator.
