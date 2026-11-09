#pragma once
#include "bootargs.h"
#ifndef VRAM_OBS_PA	/* OBSERVED-BY-US (task 09): ADT vram@D3110000 of this Mac, J714s panel 3024x1964 */
#define VRAM_OBS_PA 0x105D3110000ULL
#define VRAM_OBS_SIZE 0x57AC000ULL
#define VRAM_OBS_W 3024
#define VRAM_OBS_H 1964
#endif
#ifndef DRAM_OBS_BASE	/* spec §3 [OURS]: /chosen dram-base, dram-size (24 GiB) */
#define DRAM_OBS_BASE 0x10000000000ULL
#define DRAM_OBS_SIZE 0x600000000ULL
#endif
struct fbsel {
	uint64_t pa, size, w, h, stride;	/* pa = ~0 if none */
	int fmt30, tier;			/* tier 'a', 'b', 'c' (see probefb.c) or '-' */
	int adt_ok, vram_ok;
	uint64_t vram_base, vram_size;		/* runtime ADT /vram, if vram_ok */
};
/* Task 09 FB selection; reads only. 0 if s->pa is usable (whole FB inside a vram region). */
int probe_fb(const struct bootargs *ba, struct fbsel *s);
int probe_vram(const struct bootargs *ba, uint64_t *base, uint64_t *size, int *adt_ok);
