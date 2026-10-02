#include "FolioArchive.h"
#include <string.h>

/* Independent implementation of the RIPEMD-128 specification:
   https://homes.esat.kuleuven.be/~bosselae/ripemd/rmd128.txt
   Word loads/stores are explicit, so unaligned data and either host endian work. */
static uint32_t load32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void store32(uint8_t *p, uint32_t x) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(x >> (8 * i));
}

static uint32_t rotate(uint32_t x, unsigned n) { return x << n | x >> (32 - n); }

static uint32_t boolean(unsigned round, uint32_t x, uint32_t y, uint32_t z) {
    switch (round) {
        case 0: return x ^ y ^ z;
        case 1: return (x & y) | (~x & z);
        case 2: return (x | ~y) ^ z;
        default: return (x & z) | (y & ~z);
    }
}

static void ripemd_block(uint32_t h[4], const uint8_t block[64]) {
    static const uint8_t order[2][64] = {
        {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
         7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
         3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
         1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2},
        {5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
         6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
         15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
         8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14}
    };
    static const uint8_t shifts[2][64] = {
        {11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
         7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
         11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
         11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12},
        {8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
         9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
         9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
         15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8}
    };
    static const uint32_t constants[2][4] = {
        {0, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc},
        {0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0}
    };
    uint32_t words[16], lanes[2][4];
    for (unsigned i = 0; i < 16; ++i) words[i] = load32(block + i * 4);
    memcpy(lanes[0], h, 16);
    memcpy(lanes[1], h, 16);
    for (unsigned step = 0; step < 64; ++step) {
        for (unsigned lane = 0; lane < 2; ++lane) {
            uint32_t *v = lanes[lane];
            unsigned round = step / 16;
            uint32_t t = rotate(v[0] + boolean(lane ? 3 - round : round, v[1], v[2], v[3])
                                + words[order[lane][step]] + constants[lane][round], shifts[lane][step]);
            v[0] = v[3]; v[3] = v[2]; v[2] = v[1]; v[1] = t;
        }
    }
    uint32_t merged[4] = {h[1] + lanes[0][2] + lanes[1][3],
                          h[2] + lanes[0][3] + lanes[1][0],
                          h[3] + lanes[0][0] + lanes[1][1],
                          h[0] + lanes[0][1] + lanes[1][2]};
    memcpy(h, merged, sizeof(merged));
}

int folio_ripemd128(const uint8_t *input, size_t size, uint8_t output[16]) {
    if ((!input && size) || !output) return -1;
    uint32_t h[4] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476};
    uint64_t bits = (uint64_t)size * 8;
    while (size >= 64) { ripemd_block(h, input); input += 64; size -= 64; }
    uint8_t tail[128] = {0};
    if (size) memcpy(tail, input, size);
    tail[size] = 0x80;
    size_t padded = size < 56 ? 64 : 128;
    for (unsigned i = 0; i < 8; ++i) tail[padded - 8 + i] = (uint8_t)(bits >> (8 * i));
    ripemd_block(h, tail);
    if (padded == 128) ripemd_block(h, tail + 64);
    for (unsigned i = 0; i < 4; ++i) store32(output + 4 * i, h[i]);
    return 0;
}

/* MDict's feedback uses the preceding CIPHERTEXT byte, starting at 0x36. */
int folio_mdict_fast_decrypt(uint8_t *data, size_t size, const uint8_t *key, size_t key_size) {
    if ((!data && size) || !key || !key_size) return -1;
    uint8_t previous = 0x36;
    for (size_t i = 0; i < size; ++i) {
        uint8_t cipher = data[i];
        data[i] = (uint8_t)((cipher >> 4 | cipher << 4) ^ previous ^ (uint8_t)i ^ key[i % key_size]);
        previous = cipher;
    }
    return 0;
}

/* Salsa quarter round, applied first to columns and then to rows.
   Four double rounds implement the eight-round variant used by MDict. */
static void salsa_quarter(uint32_t x[16], unsigned a, unsigned b, unsigned c, unsigned d) {
    x[b] ^= rotate(x[a] + x[d], 7);
    x[c] ^= rotate(x[b] + x[a], 9);
    x[d] ^= rotate(x[c] + x[b], 13);
    x[a] ^= rotate(x[d] + x[c], 18);
}

int folio_salsa20_8_xor(uint8_t *data, size_t size, const uint8_t *key, size_t key_size,
                      const uint8_t nonce[8], uint64_t counter) {
    if ((!data && size) || !key || !nonce || (key_size != 16 && key_size != 32)) return -1;
    const uint8_t *constant = (const uint8_t *)(key_size == 16 ? "expand 16-byte k" : "expand 32-byte k");
    uint32_t state[16] = {0};
    for (unsigned i = 0; i < 4; ++i) {
        state[i * 5] = load32(constant + i * 4);
        state[1 + i] = load32(key + i * 4);
        state[11 + i] = load32(key + (key_size == 32 ? 16 : 0) + i * 4);
    }
    state[6] = load32(nonce); state[7] = load32(nonce + 4);
    state[8] = (uint32_t)counter; state[9] = (uint32_t)(counter >> 32);
    while (size) {
        uint32_t work[16];
        uint8_t stream[64];
        memcpy(work, state, sizeof(work));
        for (unsigned round = 0; round < 4; ++round) {
            for (unsigned i = 0; i < 4; ++i)
                salsa_quarter(work, i * 5, (i * 5 + 4) % 16, (i * 5 + 8) % 16, (i * 5 + 12) % 16);
            for (unsigned i = 0; i < 4; ++i) {
                unsigned base = i * 4;
                salsa_quarter(work, base + i, base + (i + 1) % 4, base + (i + 2) % 4, base + (i + 3) % 4);
            }
        }
        for (unsigned i = 0; i < 16; ++i) store32(stream + i * 4, work[i] + state[i]);
        size_t count = size < 64 ? size : 64;
        for (size_t i = 0; i < count; ++i) data[i] ^= stream[i];
        data += count; size -= count;
        if (++state[8] == 0) ++state[9];
    }
    return 0;
}
