#include "FolioArchive.h"
#include <zlib.h>
#include <limits.h>
#include <string.h>

_Static_assert(sizeof(size_t) >= sizeof(uint64_t), "Folio requires 64-bit buffer addressing");
_Static_assert(sizeof(void *) >= sizeof(uint64_t), "Folio requires 64-bit pointers");

int folio_inflate(const uint8_t *input, uint64_t input_size, uint8_t *output, uint64_t *output_size) {
    if (!output_size || (!input && input_size) || (!output && *output_size)) return Z_STREAM_ERROR;
    if (input_size > SIZE_MAX || *output_size > SIZE_MAX) return Z_BUF_ERROR;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int result = inflateInit(&stream);
    if (result != Z_OK) return result;
    uint64_t supplied = 0, written = 0, capacity = *output_size;
    do {
        if (!stream.avail_in && supplied < input_size) {
            uInt chunk = (uInt)((input_size - supplied) > UINT_MAX ? UINT_MAX : input_size - supplied);
            stream.next_in = (Bytef *)(input + (size_t)supplied);
            stream.avail_in = chunk;
            supplied += chunk;
        }
        if (!stream.avail_out && written < capacity) {
            uInt chunk = (uInt)((capacity - written) > UINT_MAX ? UINT_MAX : capacity - written);
            stream.next_out = output + (size_t)written;
            stream.avail_out = chunk;
        }
        uInt available = stream.avail_out;
        result = inflate(&stream, Z_NO_FLUSH);
        written += (uint64_t)(available - stream.avail_out);
        if (result == Z_OK && (!stream.avail_out && written == capacity)) { result = Z_BUF_ERROR; break; }
    } while (result == Z_OK);
    if (result == Z_STREAM_END) result = supplied - stream.avail_in == input_size ? Z_OK : Z_DATA_ERROR;
    *output_size = written;
    inflateEnd(&stream);
    return result;
}

uint32_t folio_adler32(const uint8_t *input, size_t size) {
    if (!input && size) return 0;
    uLong checksum = adler32(0L, Z_NULL, 0);
    while (size) {
        uInt chunk = (uInt)(size > UINT_MAX ? UINT_MAX : size);
        checksum = adler32(checksum, input, chunk);
        input += chunk;
        size -= chunk;
    }
    return (uint32_t)checksum;
}
