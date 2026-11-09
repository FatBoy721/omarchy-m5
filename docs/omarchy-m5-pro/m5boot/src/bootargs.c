#include "bootargs.h"
#include <string.h>

static int plausible(uint64_t actual, uint64_t memsize)
{
	/* spec H3: memSizeActual >= memSize and a whole number of GiB (<= 16 TiB) */
	return actual && actual >= memsize && !(actual & ((1ULL << 30) - 1)) && actual <= (1ULL << 44);
}

void bootargs_parse(const void *raw, struct bootargs *ba)
{
	const uint8_t *p = raw;
	ba->revision = rd16(p + BA_REVISION);
	ba->version = rd16(p + BA_VERSION);
	ba->virt_base = rd64(p + BA_VIRT_BASE);
	ba->phys_base = rd64(p + BA_PHYS_BASE);
	ba->mem_size = rd64(p + BA_MEM_SIZE);
	ba->top_kdata = rd64(p + BA_TOP_KDATA);
	ba->v_base = rd64(p + BA_VIDEO);
	ba->v_display = rd64(p + BA_VIDEO + 8);
	ba->v_stride = rd64(p + BA_VIDEO + 16);
	ba->v_width = rd64(p + BA_VIDEO + 24);
	ba->v_height = rd64(p + BA_VIDEO + 32);
	ba->v_depth = rd64(p + BA_VIDEO + 40);
	ba->machine = rd32(p + BA_MACHINE);
	ba->dt_ptr = rd64(p + BA_DT_PTR);
	ba->dt_len = rd32(p + BA_DT_LEN);
	ba->cmdline = 0; ba->cmdline_bad = 0; ba->line_len = 0; ba->boot_flags = ba->mem_actual = 0;
	static const uint32_t lens[] = { 1024, 608 };
	for (int i = 0; i < 2; i++) {
		uint32_t off = BA_FLAGS_OFF(lens[i]);
		uint64_t actual = rd64(p + off + 8);
		if (plausible(actual, ba->mem_size)) {
			ba->line_len = lens[i];
			ba->cmdline = (const char *)p + BA_CMDLINE;
			if (strnlen(ba->cmdline, lens[i]) == lens[i]) { ba->cmdline = 0; ba->cmdline_bad = 1; }
			ba->boot_flags = rd64(p + off);
			ba->mem_actual = actual;
			break;
		}
	}
}

uint64_t ba_to_pa(const struct bootargs *ba, uint64_t x, const char **kind)
{
	if (x - ba->phys_base < ba->mem_size) { *kind = "PA"; return x; }
	if (x - ba->virt_base < ba->mem_size) { *kind = "VA"; return x - ba->virt_base + ba->phys_base; }
	*kind = "??";
	return ~0ULL;
}

uint64_t ba_fb_pa(const struct bootargs *ba, uint64_t *size, const char **kind)
{
	*kind = "no memSizeActual"; *size = 0;
	return ba->mem_actual ? ba_fb_check(ba, ba->mem_actual, size, kind) : ~0ULL;
}

uint64_t ba_fb_check(const struct bootargs *ba, uint64_t limit, uint64_t *size, const char **kind)
{
	uint32_t bpp = ba->v_depth & 0xff;	/* kBootVideoDepthMask */
	*kind = "??"; *size = 0;
	if ((bpp != 32 && bpp != 30) || !ba->v_width || !ba->v_height || ba->v_width >= 16384 ||
	    ba->v_height >= 16384 || ba->v_stride < ba->v_width * 4 || ba->v_stride > 16384 * 4) {
		*kind = "bad geometry"; return ~0ULL;
	}
	uint64_t sz = ba->v_stride * ba->v_height, x = ba->v_base;	/* < 2^16 * 2^14: no overflow */
	if (x - ba->virt_base < ba->mem_size) { *kind = "VA"; x = x - ba->virt_base + ba->phys_base; }
	else *kind = "PA";
	if (x < ba->phys_base || x - ba->phys_base > limit || sz > limit - (x - ba->phys_base)) {
		*kind = "outside DRAM"; return ~0ULL;
	}
	*size = sz;
	return x;
}
