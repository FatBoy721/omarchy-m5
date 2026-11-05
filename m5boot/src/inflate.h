#pragma once
#include "util.h"
/* RFC 1952 gzip member -> out. 0 on success (*outlen = ISIZE-checked size); <0 on error. CRC32 not checked. */
int gunzip(const uint8_t *in, uint64_t inlen, uint8_t *out, uint64_t outmax, uint64_t *outlen);
/* Uncompressed size from the gzip trailer (ISIZE, mod 2^32). */
static inline uint32_t gz_isize(const uint8_t *in, uint64_t inlen) { return rd32(in + inlen - 4); }
