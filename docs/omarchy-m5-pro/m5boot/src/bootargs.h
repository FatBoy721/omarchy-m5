#pragma once
#include "util.h"

/* Our own description of XNU's struct boot_args (pexpert/pexpert/arm64/boot.h @f6217f89),
 * decoded field-by-field at explicit LP64 offsets. */
#define BA_REVISION	0
#define BA_VERSION	2
#define BA_VIRT_BASE	8
#define BA_PHYS_BASE	16
#define BA_MEM_SIZE	24
#define BA_TOP_KDATA	32
#define BA_VIDEO	40	/* 6 x u64: base, display, rowBytes, width, height, depth */
#define BA_MACHINE	88
#define BA_DT_PTR	96
#define BA_DT_LEN	104
#define BA_CMDLINE	108
/* bootFlags follows CommandLine[BOOT_LINE_LENGTH], aligned to 8. */
#define BA_FLAGS_OFF(linelen)	(((BA_CMDLINE + (linelen)) + 7) & ~7)

struct bootargs {
	uint16_t revision, version;
	uint64_t virt_base, phys_base, mem_size, top_kdata;
	uint64_t v_base, v_display, v_stride, v_width, v_height, v_depth;
	uint32_t machine;
	uint64_t dt_ptr;
	uint32_t dt_len;
	const char *cmdline;	/* NULL if the layout is unknown or the line is not NUL-terminated */
	int cmdline_bad;	/* layout known but CommandLine has no NUL within BOOT_LINE_LENGTH */
	uint32_t line_len;	/* 1024 or 608 (spec H3), 0 = unknown */
	uint64_t boot_flags, mem_actual;
};

void bootargs_parse(const void *raw, struct bootargs *ba);
/* Physical address for a boot_args pointer (spec H4): PA if inside [physBase, +memSize),
 * converted if inside [virtBase, +memSize), else ~0. *kind = "PA"/"VA"/"??". */
uint64_t ba_to_pa(const struct bootargs *ba, uint64_t p, const char **kind);
/* Framebuffer: spec §3 puts video memory ABOVE physBase+memSize, so ba_to_pa's RAM-window test does
 * not apply. Requires memSizeActual (no layout => no console). Validates 30/32 bpp,
 * width/height < 16384, width*4 <= stride <= 16384*4, then: VA window -> convert; else PA if the
 * whole FB lies in [physBase, physBase+memSizeActual). Returns ~0 if unusable. *size = stride*height. */
uint64_t ba_fb_pa(const struct bootargs *ba, uint64_t *size, const char **kind);
/* Same geometry/DRAM checks with an explicit DRAM size: the probe's layout-independent tier
 * (Video sits at fixed offset 40; BOOT_LINE_LENGTH only moves bootFlags/memSizeActual). */
uint64_t ba_fb_check(const struct bootargs *ba, uint64_t limit, uint64_t *size, const char **kind);
