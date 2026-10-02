#ifndef FOLIO_ARCHIVE_H
#define FOLIO_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
int folio_inflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t *output_size);
uint32_t folio_adler32(const uint8_t *input, size_t size);
#endif
