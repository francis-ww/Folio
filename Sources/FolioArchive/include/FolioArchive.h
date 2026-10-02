#ifndef FOLIO_ARCHIVE_H
#define FOLIO_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
/* Buffer sizes are 64-bit. File offsets/seeks use Swift FileHandle's UInt64 API.
 * This module does not open files or call fseek/ftell. Pointer indexing uses
 * native size_t, which is required to be 64-bit on Folio's supported targets. */
int folio_inflate(const uint8_t *input, uint64_t input_size, uint8_t *output, uint64_t *output_size);
uint32_t folio_adler32(const uint8_t *input, size_t size);
/* Return 0 on success, -1 for invalid pointers or key sizes. Empty data may be NULL. */
int folio_ripemd128(const uint8_t *input, size_t size, uint8_t output[16]);
int folio_mdict_fast_decrypt(uint8_t *data, size_t size, const uint8_t *key, size_t key_size);
/* In-place Salsa20/8 XOR; nonce is exactly 8 bytes, key is 16 or 32 bytes. */
int folio_salsa20_8_xor(uint8_t *data, size_t size, const uint8_t *key, size_t key_size,
                      const uint8_t nonce[8], uint64_t counter);
#endif
