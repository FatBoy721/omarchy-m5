#include <string.h>
#include <stdint.h>

/* Word-wise fast paths: with the MMU off every access is uncached, so byte loops are very slow. */
void *memcpy(void *d, const void *s, size_t n) { return memmove(d, s, n); }
void *memmove(void *d, const void *s, size_t n)
{
	unsigned char *dp = d; const unsigned char *sp = s;
	int aligned = !(((uintptr_t)dp | (uintptr_t)sp) & 7);
	if (dp < sp) {
		if (aligned) for (; n >= 8; n -= 8, dp += 8, sp += 8) *(uint64_t *)dp = *(const uint64_t *)sp;
		while (n--) *dp++ = *sp++;
	} else {
		if (aligned) while (n & 7) { n--; dp[n] = sp[n]; }
		if (aligned) for (; n >= 8; n -= 8) *(uint64_t *)(dp + n - 8) = *(const uint64_t *)(sp + n - 8);
		while (n--) dp[n] = sp[n];
	}
	return d;
}
void *memset(void *d, int c, size_t n)
{
	unsigned char *p = d;
	while (n && ((uintptr_t)p & 7)) { *p++ = c; n--; }
	uint64_t w = 0x0101010101010101ULL * (unsigned char)c;
	for (; n >= 8; n -= 8, p += 8) *(uint64_t *)p = w;
	while (n--) *p++ = c;
	return d;
}
int memcmp(const void *a, const void *b, size_t n)
{
	const unsigned char *x = a, *y = b;
	for (; n; n--, x++, y++) if (*x != *y) return *x - *y;
	return 0;
}
void *memchr(const void *s, int c, size_t n)
{
	const unsigned char *p = s;
	for (; n; n--, p++) if (*p == (unsigned char)c) return (void *)p;
	return 0;
}
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
size_t strnlen(const char *s, size_t m) { size_t n = 0; while (n < m && s[n]) n++; return n; }
char *strrchr(const char *s, int c)
{
	const char *r = 0;
	do if (*s == (char)c) r = s; while (*s++);
	return (char *)r;
}
int strcmp(const char *a, const char *b)
{
	while (*a && *a == *b) a++, b++;
	return (unsigned char)*a - (unsigned char)*b;
}
