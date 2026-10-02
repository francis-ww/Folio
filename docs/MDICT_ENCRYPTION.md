# MDict v2 encryption

Folio automatically imports self-contained encrypted MDX dictionaries and matching MDD resources. Decryption, decompression, record streaming, and SQLite indexing run on `DictionaryLibrary`'s background actor. Existing size limits, Adler-32 checks, cancellation checks, and transaction rollback still apply.

## Header flags and cipher selection

The header's `Encrypted` attribute accepts `No`/`0`, `Yes`/`1`, `2`, and `3`; `3` sets both bits. Invalid values and unknown bits produce descriptive errors.

The v2 header bits and the individual block cipher markers describe different parts of the file:

| Location | Marker | Decryption/key derivation |
| --- | --- | --- |
| Keyword block **info/index** | `Encrypted & 2` | Fast XOR/nibble rotation; key = RIPEMD-128(checksum bytes + little-endian `0x3695`). Preserve its first eight bytes and decrypt the entire remaining payload before zlib decompression. |
| Forty-byte numeric keyword metadata | `Encrypted & 1` | Registration-bound v2 files use Salsa20/8 with an externally supplied dictionary key. The following checksum is over the plaintext metadata. |
| Individual keyword/record block payload | Descriptor cipher `1` | Fast XOR/nibble rotation; self-contained key = RIPEMD-128(the four stored checksum bytes). |
| Individual keyword/record block payload | Descriptor cipher `2` | Salsa20/8 with the same checksum-derived key, an eight-byte zero nonce, and initial counter zero. |

These mappings follow [writemdict](https://github.com/zhansliu/writemdict/blob/f0240b30cabd2f0470d3ee1a0641fc7f8c38dcf5/writemdict.py) and [mdict-analysis](https://github.com/hehonghui/mdict-analysis/blob/373ef1835d7eb47be699e3f333aa9008a7076236/readmdict.py). In particular, bit 2 does **not** select Salsa20/8 for the v2 keyword index, and bit 1 alone does **not** select fast decryption for every record block.

Each block's first little-endian 32-bit descriptor stores compression in bits 0–3, cipher in bits 4–7, and encrypted prefix length in bits 8–15. Decrypt only that prefix, capped at the actual payload length, and retain the remaining bytes. After decryption, decompress and validate the complete plaintext size/checksum. Supported compression remains zlib or none; LZO remains unsupported. Each block resets cipher state.

## Registration-bound files

When bit 1 is set and the keyword metadata checksum does not match the stored bytes, Folio throws `MDictError.passcodeRequired` before interpreting those bytes as section sizes. A plaintext preamble with a valid checksum can still be read; individual blocks retain their own cipher descriptors.

For registered v2 dictionaries, a header `RegCode` is not sufficient to recover the key: decrypting it also requires the owner's external email/device identity or passcode. Folio does not guess credentials or bypass registration, and currently has no passcode-entry API. Failed imports leave the previous library intact. This applies equally to MDX and MDD files, including `Encrypted="Yes"` and combined flags `3`.

MDict v3 UUID-derived encryption has a different format and remains outside this v2 reader's scope.

## Implementation and verification

`Sources/FolioArchive/FolioCrypto.c` implements RIPEMD-128, Salsa20/8 (16/32-byte keys), and fast decryption using bounded stack storage and explicit byte-order conversions. It introduces no crypto runtime dependency. `Sources/FolioCore/Dictionary/ArchiveDecryption.swift` provides checked Swift wrappers and format-specific key derivation. RIPEMD-128 follows the [authors' specification](https://homes.esat.kuleuven.be/~bosselae/ripemd/rmd128.txt).

`Tests/FolioCoreTests/Fixtures/encrypted.mdx` contains an actually encrypted keyword index, rather than plaintext labeled encrypted. The matching `encrypted.mdd` additionally mixes fast and Salsa-encrypted blocks. Additional MDX fixtures cover both ciphers with zlib and uncompressed payloads. Records deliberately span blocks, aliases share offsets, and resources contain an original one-pixel PNG and silent WAV. Registration fixtures encrypt the numeric preamble with a known test-only private passcode and preserve the plaintext checksum.

`MDictEncryptionTests` verifies indexing, exact definition lookup, redirects/aliases, complete media bytes, corrupted indexes, malformed blocks, passcode errors, and batch rollback. Its 15 RIPEMD, 54 Salsa, and 7 fast-cipher vectors were generated independently of the production C implementation. They include empty data, RIPEMD padding boundaries and the million-`a` vector, partial/multiple Salsa blocks, 128/256-bit keys, counter carry/wrap, and the fast cipher's 256-byte index wrap.

Regenerate only these fixtures:

```sh
python3 Scripts/generate_encryption_fixtures.py
```

The generator downloads commit-pinned upstream test references into ignored `.tools/mdict-reference` and verifies their SHA-256 hashes. It uses `writemdict`'s encryption/hash/cipher routines and independently checks archive blocks with `mdict-analysis`'s decoder. Its own record concatenation handles cross-block fixtures, which the reference reader's `items()` iterator does not reassemble. Upstream source/license notices remain in the cached reference files; they are not bundled into Folio. Golden outputs are checked in, so normal Swift test runs are offline once package dependencies are available.
