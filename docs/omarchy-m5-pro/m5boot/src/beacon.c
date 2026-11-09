/* build/m5boot-beacon.bin (task 10 + addendum): a screen-independent output channel. After the start.S PROBE entry
 * (VBAR, then the WDT disable): read boot_args Video at its FIXED offsets, compute a 4-bit code, re-arm watchdog
 * WD1 to bite after T = 20 + 10*code seconds, paint (fixed-offset FB if strictly sane, else the vram tiers),
 * clean the painted range to PoC, then wfe. An exception beacons T = 10 s. Table: NOTES.md "Task 10".
 *
 * WDT sequence = Linux drivers/watchdog/apple_wdt.c (GPL-2.0-only OR MIT, ref/linux/apple_wdt.c):
 *   apple_wdt_set_timeout(): writel(0, WD1_CUR_TIME); writel(clk_rate * t, WD1_BITE_TIME);
 *   apple_wdt_start():       writel(0, WD1_CUR_TIME); writel(CTRL_RESET_EN, WD1_CTRL);
 * clk_rate = 24 MHz: the J714s DTB (spec/inputs.md) gives the watchdog `clocks = <&clkref>`, a fixed-clock with
 * clock-frequency 0x16e3600 = 24,000,000.
 * Owner-authorised exception (task 10) to the CLAUDE.md WDT rule: writes only to WD1_CUR_TIME/BITE_TIME/CTRL
 * (+0x10/+0x14/+0x1c) of the WDT at WDT_PA. */
#include "beacon.h"
#include "adt.h"

/* Addendum 1: boot_args Video at fixed offsets (0x28 base, 0x38 rowBytes, 0x40 width, 0x48 height, 0x50 depth;
 * XNU boot.h, the same offsets bootargs_parse uses). Strictly the J714s panel: 3024x1964, stride 12096, 30/32 bpp. */
int beacon_geom(const struct bootargs *ba)
{
	uint32_t bpp = ba->v_depth & 0xff;
	return ba->v_width == VRAM_OBS_W && ba->v_height == VRAM_OBS_H && ba->v_stride == VRAM_OBS_W * 4 &&
	       (bpp == 30 || bpp == 32);
}

/* Fixed-offset FB PA if strictly sane and wholly inside DRAM, else ~0. */
uint64_t beacon_fixed_fb(const struct bootargs *ba, uint64_t dbase, uint64_t dsize)
{
	if (!beacon_geom(ba)) return ~0ULL;
	uint64_t x = ba->v_base, sz = ba->v_stride * ba->v_height;
	if (x < dbase || x - dbase > dsize || sz > dsize - (x - dbase)) return ~0ULL;
	return x;
}

/* Addendum 3, 4 bits in PM priority order (entry reached is implied by any reset):
 * bit3 MMU on at entry (SCTLR.M), bit2 D-cache on at entry (SCTLR.C), bit1 Video base == vram base,
 * bit0 Video geometry sane. Dropped (did not fit): layout matched, boot_args sanity. */
int beacon_code(uint64_t sctlr, const struct bootargs *ba, uint64_t vram_base)
{
	return (sctlr & 1 ? 8 : 0) | (sctlr & 4 ? 4 : 0) | (ba->v_base == vram_base ? 2 : 0) | (beacon_geom(ba) ? 1 : 0);
}

uint32_t beacon_seconds(int code)
{
	if (code < 0 || code > 15) return BEACON_EXC_SECONDS;
	return 20 + 10 * code;	/* <= 170 s: 170 * 24e6 < 2^32 */
}

void wdt_beacon(volatile uint32_t *wdt, uint32_t seconds)
{
	wdt[0x10 / 4] = 0;				/* WD1_CUR_TIME */
	wdt[0x14 / 4] = WDT_RATE * seconds;		/* WD1_BITE_TIME */
	wdt[0x10 / 4] = 0;				/* WD1_CUR_TIME */
	wdt[0x1c / 4] = 4;				/* WD1_CTRL = CTRL_RESET_EN */
#ifndef HOST
	__asm__ volatile("dsb sy" ::: "memory");
#endif
}

/* Task 11 addendum (beacon3): exception (or failed check) at stage s -> 10 + 10*s s; full success -> 175 s. */
uint32_t beacon3_seconds(uint32_t stage, int success)
{
	if (success) return BEACON3_OK_SECONDS;
	return 10 + 10 * (stage > 16 ? 16 : stage);	/* 0..16 -> 10..170 s */
}

#if !defined(HOST) && !defined(GZ3)	/* gz3 (task 12) links only the helpers above; main.c has its own main */
#ifndef WDT_PA
#define WDT_PA 0x28836C000
#endif
void dcache_civac_range(uint64_t start, uint64_t len);
extern volatile uint32_t beacon_stage;	/* start.S .data: stages 0-4 set in asm, 5-15 here */
static int in_exc;

void __attribute__((noreturn)) probe_exception(void)
{
	if (!in_exc++) wdt_beacon((volatile uint32_t *)WDT_PA, beacon3_seconds(beacon_stage, 0));
	for (;;) __asm__ volatile("wfe");
}

/* Set the stage BEFORE each operation. VM only: a test hook faults at a chosen stage, read from the u32 at
 * 0x44020000 (QEMU loader writes stage+1 there; 0 = no hook). Never on hardware. */
#ifdef VM
#define STAGE(n) do { beacon_stage = (n); if (*(volatile uint32_t *)0x44020000 == (n) + 1u) __asm__ volatile("brk #0x55"); } while (0)
#else
#define STAGE(n) do { beacon_stage = (n); } while (0)
#endif
/* A failed check halts the run with the same timing as an exception at that stage. */
static void __attribute__((noreturn)) fail(void) { probe_exception(); }

/* Addendum 2: paint, then clean+invalidate the painted range to PoC (dcache_civac_range ends with dsb sy). */
static void paint(uint64_t pa, uint64_t w, uint64_t h, uint64_t stride, uint32_t colour)
{
	for (uint64_t y = 0; y < h; y++)
		for (uint64_t x = 0; x < w; x++)
			((volatile uint32_t *)(pa + y * stride))[x] = colour;
	dcache_civac_range(pa, stride * h);
}
#define GREEN 0x000ffc00u	/* x2r10g10b10: G = bits 10..19 */
#define MAGENTA 0x3ff003ffu
_Static_assert((uint64_t)VRAM_OBS_W * 4 * VRAM_OBS_H <= VRAM_OBS_SIZE, "green paint must stay inside the vram region");

/* beacon3 (task 11 addendum): stage-coded. Reads only, except the paint (a strictly-sane fixed-offset FB inside
 * DRAM) and the final WDT arm. Stages 5..15 as in NOTES.md "Task 11". */
void main(uint64_t x0)
{
	struct bootargs ba;
	const char *k;
	STAGE(5);	/* owner: visible output ASAP, before touching boot_args: GREEN over the OBSERVED vram region */
	paint(VRAM_OBS_PA, VRAM_OBS_W, VRAM_OBS_H, VRAM_OBS_W * 4, GREEN);
	STAGE(6);	/* x0 as a pointer: non-zero, 8-aligned, inside the observed DRAM */
	if (!x0 || (x0 & 7) || x0 < DRAM_OBS_BASE || x0 - DRAM_OBS_BASE >= DRAM_OBS_SIZE) fail();
	STAGE(7);	/* boot_args header */
	uint16_t rev = rd16((const void *)x0), ver = rd16((const uint8_t *)x0 + 2);
	if (rev < 1 || rev > 2 || ver < 1 || ver > 2) fail();
	STAGE(8);	/* Video fields (fixed offsets) and the rest of boot_args */
	bootargs_parse((const void *)x0, &ba);
	STAGE(9);	/* FB sanity against the observed DRAM (the ADT is not read yet) */
	uint64_t fb = beacon_fixed_fb(&ba, DRAM_OBS_BASE, DRAM_OBS_SIZE);
	if (fb != ~0ULL) {
		STAGE(10);	/* boot_args FB paint started (magenta) */
		paint(fb, ba.v_width, ba.v_height, ba.v_stride, MAGENTA);
		STAGE(11);	/* paint + clean done */
	}
	STAGE(12);	/* deviceTreeP */
	uint64_t dt = ba_to_pa(&ba, ba.dt_ptr, &k);
	if (dt == ~0ULL || !ba.dt_len || ba.dt_len > ba.mem_size - (dt - ba.phys_base)) fail();
	STAGE(13);	/* ADT header */
	struct adt a = { (const uint8_t *)dt, ba.dt_len };
	if (ba.dt_len < 8 || rd32(a.base) > 0x10000 || rd32(a.base + 4) > 0x10000) fail();
	STAGE(14);	/* ADT walk */
	if (adt_child(&a, 0, "chosen") < 0) fail();
	STAGE(15);	/* /vram lookup */
	uint64_t vb, vs; int ok;
	if (probe_vram(&ba, &vb, &vs, &ok)) fail();
	STAGE(16);	/* everything done */
	wdt_beacon((volatile uint32_t *)WDT_PA, beacon3_seconds(16, 1));
	for (;;) __asm__ volatile("wfe");
}
#endif
