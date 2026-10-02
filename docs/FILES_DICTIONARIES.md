# Dictionaries in the Files app

Folio uses its standard **Documents** directory as the dictionary folder. Its SQLite index, scan manifest, vocabulary store, and practice history stay in **Application Support**, outside the shared folder.

## Add dictionaries on iPhone or iPad

1. Open Folio once to create its folder.
2. Open the iOS **Files** app. In **Browse**, open **On My iPhone → Folio** (or **On My iPad → Folio**).
3. Copy or paste your `.mdx` dictionary directly into this folder. If it has multimedia resources, add the `.mdd` with the same base name, such as `Oxford.mdx` and `Oxford.mdd`. Extensions and base-name matching are case insensitive. Subfolders and numbered MDD sets are not scanned.
4. Let the copy finish, then return to Folio. Scanning starts automatically on launch and when the app returns to the foreground.
5. Open **Library → Refresh Dictionaries** (**文库 → 重新扫描词库**) to scan manually, or pull down on Library. A background progress indicator and any file-specific issues appear here.
6. Enable the dictionary under **Dictionary sources** and set its priority with **Reorder**. Lookup and pronunciation use the local index and resources.

Library's **Open Files App / 打开文件应用** button opens `shareddocuments://`. It does not promise to navigate straight into Folio. If iOS cannot open this scheme, the app explains how to open Files manually. On an empty library, a bilingual card provides the folder path and matching-filename instructions.

## Change or remove dictionaries

- Replace a dictionary file in Files, then return to Folio or refresh. Unchanged files are skipped using persistent filename, size, modification-time, and file-identity metadata; the scanner does not hash or read whole archives to detect changes.
- Add an MDD later to attach its resources. Replacing or removing an MDD rebuilds or clears its resources while preserving indexed entries and their IDs.
- If you delete an MDX in Files, the next scan removes its indexed dictionary. An orphan MDD remains in Files, with a message explaining that it needs a matching MDX.
- **Remove dictionary and resources** in Library deletes the managed MDX and matching MDD from the shared folder as well as the index. Saved vocabulary and practice history remain. Removal is unavailable while a scan runs.
- Existing dictionaries imported by earlier Folio versions remain usable. They are not deleted just because Documents is empty: those versions stored parsed records rather than original archives. To manage such a dictionary in Files, copy its original MDX/MDD files into Folio with the same filename stem. The next scan adopts that dictionary and preserves its source ID and selection preferences.

Each changed MDX/MDD pair commits with its manifest in one SQLite transaction. A corrupt, incomplete, unsupported, or passcode-bound update leaves the previously indexed pair intact and remains eligible for retry. Other pairs continue indexing independently. Failed directory enumeration never removes existing dictionaries.

## Background scanning and large files

`DocumentsDictionaryScanner` is an actor; it enumerates metadata and queues one pair at a time through `DictionaryLibrary`. Concurrent lifecycle/manual requests share the scan and request a final pass, avoiding parallel copies of a large import. The root SwiftUI hierarchy appears before scanning begins. Documents paths are app-owned and require no security-scoped access calls or bookmarks.

On Apple platforms, `ArchiveFileAccess` batches file coordination and holds coordinated reads while a pair is indexed. This follows [Apple's batch coordination guidance](https://developer.apple.com/documentation/foundation/nsfilecoordinator/prepare(forreadingitemsat:options:writingitemsat:options:error:byaccessor:)). Size/time/identity checks before and after parsing additionally reject a file that changes during indexing. File deletion is coordinated and restricted to regular files directly inside the owned folder; symbolic links are rejected.

The parser streams bounded compressed/expanded blocks and individual records into SQLite. A 1 GB MDD is never loaded into one `Data` value. Existing limits remain: one million keys, 100,000 blocks per section, 64 MiB per block, 32 MiB per record, and 8 GiB expanded record data. Memory still depends on block sizes and keyword metadata. Initial indexing takes time and requires disk space for the original archives plus the SQLite resource index. Dictionary reads serialize behind an active pair transaction while SwiftUI remains responsive; subsequent unchanged scans avoid parsing entirely.

The app enables both `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`. Apple describes their combined Files visibility in the [property-list reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html).

## Verification

Core tests cover case-insensitive automatic pairing, entry/resource lookup, persisted unchanged detection after reopening SQLite, delayed MDD addition, MDD replacement/removal, failed replacement rollback and retry, independent pair failures, orphan resources, external deletion, legacy/sample preservation, owned-file removal, ignored subfolders, symbolic-link rejection, concurrent requests, and rejection of a sparse 1 GB invalid MDD without loading the whole file. All existing parser, encryption, lookup, online, localization, and FSRS tests remain in the suite.

Native simulator tests cover recovery of Library's scan state after directory-access failure, and the Files guide at 320-point width with large accessibility text in English/Chinese and light/dark appearances. The macOS **Swift and iOS checks** GitHub workflow builds and runs these native tests. Windows/WSL checks cannot verify Apple file coordination, the Files URL scheme, or actual iPhone memory usage.

On a device, verify:

1. Folio appears in Files after first launch; paste a real MDX/MDD pair and return to the app.
2. Search an entry, open its HTML, and play an MDD pronunciation resource.
3. Refresh twice and confirm unchanged dictionaries remain available without repeated indexing.
4. Add and replace an MDD, delete an MDX, and confirm Library follows these changes while retaining saved words.
5. Copy a supported large real MDD, including a copy still in progress. Check touch responsiveness and profile peak memory with Instruments. A sparse invalid-file regression test does not replace this measurement.
6. Check the Open Files button and guide in both languages, both appearances, and on iPad.
