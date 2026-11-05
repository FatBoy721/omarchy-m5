/* Host test: gunzip vs python gzip at levels 0/1/9, plus the real Image.gz if given. Truncation must fail. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "inflate.h"
static uint8_t *rd(const char *p, long *n) { FILE *f = fopen(p, "rb"); if (!f) return 0; fseek(f, 0, 2); *n = ftell(f); rewind(f);
	uint8_t *b = malloc(*n); fread(b, 1, *n, f); fclose(f); return b; }
int main(int argc, char **argv)
{
	for (int i = 1; i + 1 < argc; i += 2) {
		long gn, rn; uint8_t *g = rd(argv[i], &gn), *r = rd(argv[i + 1], &rn);
		assert(g && r);
		uint8_t *o = malloc(rn + 1); uint64_t on;
		assert(gunzip(g, gn, o, rn, &on) == 0 && on == (uint64_t)rn && !memcmp(o, r, rn));
		assert(gz_isize(g, gn) == (uint32_t)rn);
		assert(gunzip(g, gn, o, rn - 1, &on) < 0);	/* output bound */
		assert(gunzip(g, gn / 2, o, rn, &on) < 0);	/* truncated input */
		printf("test_inflate: ok %s (%ld -> %ld)\n", argv[i], gn, rn);
		free(g); free(r); free(o);
	}
	return 0;
}
