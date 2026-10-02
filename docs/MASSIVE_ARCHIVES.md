# Massive MDX/MDD indexing

Folio now indexes keywords and definitions in disk-backed SQLite batches, and reads MDD resources on demand. Installing a multi-gigabyte MDD does not copy its payload into SQLite or load it into memory. MDX definitions become available before MDD indexing starts; a missing, pending, or invalid MDD leaves definitions readable.

## What changed

- `ArchiveFile` uses `FileHandle.seek(toOffset: UInt64)` and checks every seek/read against the file length. Section sizes, keyword record offsets, compressed file positions, and expanded positions use `UInt64`; SQLite stores validated `Int64` positions. Additions use `addingReportingOverflow`, and conversions to buffer `Int` happen only after bounded-size checks. Apple's [FileHandle API](https://developer.apple.com/documentation/foundation/filehandle/seek(tooffset:)) accepts a 64-bit offset.
- `FolioArchive` performs compression and crypto, not file I/O; it contained no `fseek` or `ftell` calls. Its inflate ABI now uses explicit `uint64_t` lengths, checks pointers, and supplies bounded chunks to zlib while tracking progress in 64-bit counters. Compile-time checks require 64-bit native pointers and `size_t` on supported targets.
- `MDictReader` persists keywords to SQLite instead of retaining a dictionary-sized keyword array. Each keyword/block-descriptor transaction writes at most 1,000 rows. Definitions are consumed individually, with at most 1,000 words or a 4 MiB raw-content budget in each transaction. The import actor calls `await Task.yield()` after every batch, and an explicit autorelease pool drains Foundation temporaries. [Swift documents yielding as an opportunity for other tasks to run](https://docs.swift.org/latest/documentation/swift/task/yield()).
- Definition and resource indexes are separate files under **Application Support/Folio/Indexes**. Importing uses unpublished staging files and atomically swaps their source pointers and scan manifest after validation. It does not publish a half-written definition index or copy millions of rows in a final publication transaction. Existing source IDs, dictionary selections, saved words, and practice history are retained.
- An MDD index stores normalized resource keys and 64-bit compressed/expanded block locations. Lookup seeks directly to the required blocks, decrypts/decompresses them, verifies their checksums, and reconstructs only the requested record. A single decompressed block is cached while streaming MDX definitions. The unencrypted zlib path avoids copying its packed payload into another large buffer.
- Documents scanning publishes **all MDX definitions first**, then processes MDD companions. Library and word details update after each published index. The HTML renderer reloads when its resource index becomes available.
- Pairing tries case-insensitive exact names, punctuation/version normalization (`OxfordV3.mdx` with `Oxford3.mdd`), and a unique meaningful prefix. A directory with one dictionary can use its sole resource companion. Ambiguous candidates generate warnings rather than guessing between dictionaries; exact companions take priority.
- Inspection errors are caught and logged through the `MDict` diagnostics category. Library shows **Failed to parse dictionary / 无法解析词典** with file-specific information. Errors discovered during lazy resource access also surface beside the definition. Corrupt, missing, changing, unsupported, and passcode-bound files produce errors while available definitions remain usable.

The explicit `importArchives` API still publishes a selected batch atomically. Documents scanning intentionally treats MDX and MDD as separate publications so a new dictionary remains usable when its MDD fails. Failed resource replacements retain the prior resource index; fingerprints prevent reading that index from a changed archive.

## Bounds and remaining verification

The engine accepts up to ten million keywords and one million block descriptors per section. Absolute positions are bounded by SQLite's signed 64-bit range rather than a 2 GB or 8 GiB archive limit. Per-block compressed/expanded buffers remain bounded to 64 MiB, headwords/resource paths to 16 KiB, individual definitions to 4 MiB, and individual requested resources to 32 MiB. Oversized individual records or unsupported formats produce a warning; archive size alone does not determine memory use.

Keyword metadata, a bounded metadata page, decompressed blocks, and a requested resource still consume memory. These limits avoid whole-archive accumulation; they do not imply zero allocations. Full C process faults or operating-system memory termination cannot be caught by Swift `do/catch`, so bounds and bounded lifetime are applied before allocation and pointer use.

MDict v2, UTF-8/UTF-16LE, zlib/uncompressed blocks, and the existing self-contained encryption formats remain supported. LZO, external registration credentials, and numbered MDD sets remain unsupported. With lazy MDD access, record checksums/compression are checked when the resource is requested rather than decompressing every resource during startup.

## Automated verification

On Windows/WSL with Swift 6.0.3, **74 core tests pass**, including the existing encryption, lookup, localization, online, and FSRS suite.

`MassiveArchiveTests` creates an original valid sparse MDD with **2,400,000,000 bytes of logical record padding** and a resource after that boundary. It verifies:

- File seeking and SQLite block positions beyond `Int32.max`.
- Successful scanning with version-mismatched MDX/MDD filenames.
- A readable MDX definition before resource publication.
- Correct resource bytes beyond 2 GB.
- Combined definition/resource SQLite indexes below 1 MiB; payloads are not copied into the index.
- Safe rejection of an oversized individual resource.

Further tests verify 5,500 keywords written in bounded batches, searchable definitions, ambiguous pairing, arithmetic-overflow guards, invalid C pointers, corrupt lazy resource decompression, and missing resource files. The previous invalid 1 GB MDD regression now expects the MDX to remain readable.

An isolated run of the sparse-file test under Linux `/usr/bin/time -v` reported **44,032 KiB maximum RSS (43 MiB)** for the complete test process. This includes the Swift Testing runtime and fixture setup. The fixture has few keywords and sparse uncompressed padding; this is not a benchmark of the original 56.9 MB MDX/2.2 GB MDD, millions of keywords, large compressed blocks, or UIKit/WebKit memory.

Run the core suite with `swift test` on macOS, or `Scripts/test_linux.sh` with the configured Swift toolchain in WSL. Run the native app tests through the checked-in **Swift and iOS checks** GitHub workflow. Native layout tests include the warning banner in English/Chinese, light/dark appearances, and large accessibility text at 320-point width.

For the original dictionary, build the new IPA, install it over the existing app, and refresh Library. Confirm the MDX appears before MDD completion, then test images, audio, and repeated foreground scans. Apple SDK builds and Instruments/device memory profiling remain necessary; the original dictionary and an iPhone were not available in this Windows session.
