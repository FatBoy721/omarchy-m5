/* Task 09: the ONLY way the probe/gz/spin builds pick a framebuffer. NATIVE (probe2): our code runs, but the
 * task 06 DRAM check found no FB (black screen). Order (PM, task 09):
 *  (a) boot_args Video base, if the whole FB lies inside the runtime ADT /vram region (reg translated) and the
 *      geometry is sane;
 *  (b) the runtime ADT /vram base with the boot_args geometry, if it fits inside /vram;
 *  (c) LAST RESORT: the OBSERVED-BY-US vram region (our ADT dump of this Mac, reports/04-j714s-full.txt via spec,
 *      task 09: vram@D3110000 reg PA 0x105_D311_0000 size 0x57AC000) with 3024x1964, stride 3024*4, x2r10g10b10.
 *      The FB must fit inside that region, so paint stays bounded by it.
 * The selected range is always inside a vram region: never an address outside it (review G1 stays satisfied). */
#include "probefb.h"
#include "adt.h"

static int geom_ok(uint64_t w, uint64_t h, uint64_t st, uint32_t bpp)
{
	return (bpp == 30 || bpp == 32) && w && h && w < 16384 && h < 16384 && st >= w * 4 && st <= 16384 * 4;
}

static int inside(uint64_t pa, uint64_t sz, uint64_t base, uint64_t size)
{
	return pa >= base && pa - base <= size && sz <= size - (pa - base);
}

/* Runtime ADT /vram reg[0], translated. 0 on success. */
int probe_vram(const struct bootargs *ba, uint64_t *base, uint64_t *size, int *adt_ok)
{
	const char *k;
	*adt_ok = 0;
	uint64_t dt = ba_to_pa(ba, ba->dt_ptr, &k);
	if (dt == ~0ULL || !ba->dt_len || ba->dt_len > ba->mem_size - (dt - ba->phys_base)) return -1;
	struct adt a = { (const uint8_t *)dt, ba->dt_len };
	int chain[ADT_MAXDEPTH], depth;
	if (adt_child(&a, 0, "chosen") < 0) return -1;	/* sanity: the root parses */
	*adt_ok = 1;
	if (adt_path(&a, "/vram", chain, &depth) < 0) return -2;
	if (adt_reg(&a, chain, depth, 0, base, size) || !*size || *base + *size < *base) return -3;
	return 0;
}

int probe_fb(const struct bootargs *ba, struct fbsel *s)
{
	uint64_t vb = 0, vs = 0;
	int adt_ok;
	uint32_t bpp = ba->v_depth & 0xff;
	s->vram_ok = !probe_vram(ba, &vb, &vs, &adt_ok);
	s->adt_ok = adt_ok; s->vram_base = vb; s->vram_size = vs;
	s->w = ba->v_width; s->h = ba->v_height; s->stride = ba->v_stride; s->fmt30 = bpp == 30;
	s->size = s->stride * s->h;	/* < 2^16 * 2^14 when geom_ok */
	if (s->vram_ok && geom_ok(s->w, s->h, s->stride, bpp)) {
		uint64_t x = ba->v_base;
		if (x - ba->virt_base < ba->mem_size) x = x - ba->virt_base + ba->phys_base;
		if (inside(x, s->size, vb, vs)) { s->pa = x; s->tier = 'a'; return 0; }
		if (s->size <= vs) { s->pa = vb; s->tier = 'b'; return 0; }
	}
	s->w = VRAM_OBS_W; s->h = VRAM_OBS_H; s->stride = VRAM_OBS_W * 4; s->fmt30 = 1;
	s->size = s->stride * s->h;
	if (s->size <= VRAM_OBS_SIZE) { s->pa = VRAM_OBS_PA; s->tier = 'c'; return 0; }
	s->pa = ~0ULL; s->tier = '-';
	return -1;
}
