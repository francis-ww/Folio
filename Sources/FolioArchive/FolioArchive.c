#include "FolioArchive.h"
#include <zlib.h>
#include <limits.h>

int folio_inflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t *output_size) {
    if (input_size > ULONG_MAX || *output_size > ULONG_MAX) return Z_BUF_ERROR;
    uLongf length = (uLongf)*output_size;
    int result = uncompress(output, &length, input, (uLong)input_size);
    *output_size = (size_t)length;
    return result;
}

uint32_t folio_adler32(const uint8_t *input, size_t size) {
    uLong checksum = adler32(0L, Z_NULL, 0);
    while (size) {
        uInt chunk = (uInt)(size > UINT_MAX ? UINT_MAX : size);
        checksum = adler32(checksum, input, chunk);
        input += chunk;
        size -= chunk;
    }
    return (uint32_t)checksum;
}
