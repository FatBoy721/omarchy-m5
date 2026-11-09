#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

/* Little-endian, alignment-safe reads (MMU off => Device memory, no unaligned access). */
static inline uint32_t rd32(const void *p)
{
	const uint8_t *b = p;
	return b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24;
}
static inline uint16_t rd16(const void *p) { const uint8_t *b = p; return b[0] | b[1] << 8; }
static inline uint64_t rd64(const void *p) { return rd32(p) | (uint64_t)rd32((const uint8_t *)p + 4) << 32; }
static inline uint64_t align_up(uint64_t x, uint64_t a) { return (x + a - 1) & ~(a - 1); }
static inline uint64_t align_down(uint64_t x, uint64_t a) { return x & ~(a - 1); }

struct range { uint64_t base, size; };

/* fmt.c: %s %c %d %u %x with optional l/ll; %x is zero-padded to width if given (%08x). */
int m5_vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
int m5_snprintf(char *buf, size_t n, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
