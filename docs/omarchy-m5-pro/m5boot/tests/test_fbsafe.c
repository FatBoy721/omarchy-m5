/* Task 06/09 host test: (a) probe_fb tiers: a = boot_args FB wholly inside ADT /vram; b = /vram base + boot_args
 * geometry; c = the observed vram constant region; every selected FB lies wholly inside its vram region.
 * (b) the console/paint paths (fb_init, fb_puts incl. wrap, fb_rect with out-of-range coords, the probe's
 * bars/console split) never write outside [base, base + stride*height). Built with FB_SCALE=1 and 2. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "probefb.h"
#include "fb.h"

static uint8_t mem[1 << 16];	/* host "DRAM": boot_args at 0, ADT at 0x1000 */

static size_t prop(uint8_t *p, const char *n, const void *v, uint32_t l)
{
	memset(p, 0, 36); strcpy((char *)p, n); memcpy(p + 32, &l, 4); memcpy(p + 36, v, l);
	return (36 + l + 3) & ~3u;
}

static uint32_t mkadt(uint8_t *p, int with_vram, uint64_t vb, uint64_t vs)
{
	uint8_t *s = p;
	uint32_t hdr[2] = { 3, with_vram ? 2 : 1 }, two = 2;
	memcpy(p, hdr, 8); p += 8; p += prop(p, "name", "device-tree", 12);
	p += prop(p, "#address-cells", &two, 4); p += prop(p, "#size-cells", &two, 4);
	hdr[0] = 1; hdr[1] = 0;
	memcpy(p, hdr, 8); p += 8; p += prop(p, "name", "chosen", 7);
	if (with_vram) {
		uint64_t reg[2] = { vb, vs };
		hdr[0] = 2; memcpy(p, hdr, 8); p += 8; p += prop(p, "name", "vram", 5); p += prop(p, "reg", reg, 16);
	}
	return p - s;
}

static struct fbsel S;
/* boot_args with physBase = host address of mem, memSize = 0x8000 (so the ADT at +0x1000 is "in DRAM"). */
static uint64_t try(uint64_t fb, uint64_t w, uint64_t h, uint64_t st, int with_vram, uint64_t vb, uint64_t vs)
{
	uint64_t phys = (uintptr_t)mem, v[6] = { fb, 0, st, w, h, 30 };
	memset(mem, 0, 0x2000);
	uint32_t len = mkadt(mem + 0x1000, with_vram, vb, vs);
	uint64_t q[4] = { 0xfffffe0000000000ULL, phys, 0x8000, phys };
	memcpy(mem + 8, q, 32); memcpy(mem + 40, v, 48);
	uint64_t dt = phys + 0x1000; memcpy(mem + 96, &dt, 8); memcpy(mem + 104, &len, 4);
	struct bootargs ba;
	bootargs_parse(mem, &ba);
	int r = probe_fb(&ba, &S);
	assert(!r == (S.pa != ~0ULL));
	if (!r) {	/* invariant: the whole FB is inside the region its tier names */
		uint64_t rb = S.tier == 'c' ? 0x105D3110000ULL : vb, rs = S.tier == 'c' ? 0x57AC000ULL : vs;
		assert(S.pa >= rb && S.pa + S.stride * S.h <= rb + rs && S.size == S.stride * S.h);
	}
	return S.pa;
}

int main(void)
{
	uint64_t V = 0x105D3110000ULL, VS = 0x57AC000ULL, FB = 3024 * 4 * 1964ULL;
	/* tier a: boot_args FB inside /vram */
	assert(try(V, 3024, 1964, 3024 * 4, 1, V, VS) == V && S.tier == 'a' && S.vram_ok && S.adt_ok);
	assert(try(V + VS - FB, 3024, 1964, 3024 * 4, 1, V, VS) == V + VS - FB && S.tier == 'a');
	/* tier b: Video base outside /vram (the G1 address, straddling the end, below) -> /vram base */
	assert(try(0x10bd3110000ULL, 3024, 1964, 3024 * 4, 1, V, VS) == V && S.tier == 'b');
	assert(try(V + VS - FB + 4, 3024, 1964, 3024 * 4, 1, V, VS) == V && S.tier == 'b');
	assert(try(V - 4, 3024, 1964, 3024 * 4, 1, V, VS) == V && S.tier == 'b');
	/* tier c: no /vram node, /vram too small, or bad geometry -> observed region, fixed geometry */
	assert(try(0x10bd3110000ULL, 3024, 1964, 3024 * 4, 0, 0, 0) == V && S.tier == 'c' && !S.vram_ok && S.adt_ok);
	assert(try(V, 3024, 1964, 3024 * 4, 1, V, 0x1000) == V && S.tier == 'c');
	assert(try(V, 3024, 1964, 100, 1, V, VS) == V && S.tier == 'c' && S.w == 3024 && S.stride == 3024 * 4 && S.fmt30);
	assert(try(V, 0, 1964, 3024 * 4, 1, V, VS) == V && S.tier == 'c');
	puts("test_fbsafe: probe_fb ok");

	/* paint paths: guard bytes around a W x H FB with padded stride */
	const uint32_t W = 300, H = 200, ST = W * 4 + 64, GUARD = 4096;
	size_t n = (size_t)ST * H;
	uint8_t *buf = malloc(n + 2 * GUARD), *fb = buf + GUARD;
	memset(buf, 0xa5, n + 2 * GUARD);
	struct fb bars, con;
	fb_init(&bars, (uintptr_t)fb, W, H, ST);
	fb_rect(&bars, 0, 0, W, H, 0x3ff003ff);			/* full fill */
	fb_rect(&bars, W - 10, H - 10, 1000, 1000, 1);		/* clipped */
	fb_rect(&bars, 5000, 5000, 10, 10, 1);			/* fully outside */
	fb_init(&con, (uintptr_t)fb, W - 112, H, ST);		/* probe console beside the bar strip */
	for (int i = 0; i < 2000; i++) fb_puts(&con, "0123456789abcdef wrap and newline test\n");
	for (size_t i = 0; i < GUARD; i++) assert(buf[i] == 0xa5 && buf[GUARD + n + i] == 0xa5);
	for (uint32_t y = 0; y < H; y++)	/* stride padding untouched too */
		for (uint32_t x = W * 4; x < ST; x++) assert(fb[(size_t)y * ST + x] == 0xa5);
	puts("test_fbsafe: paint paths ok");
	free(buf);
	return 0;
}
