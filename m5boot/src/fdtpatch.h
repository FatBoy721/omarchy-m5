#pragma once
#include "util.h"

struct patch_in {
	struct range mem;			/* /memory */
	const struct range *rsv; int nrsv;	/* /reserved-memory no-map */
	uint64_t fb_base; uint32_t fb_w, fb_h, fb_stride;	/* fb_base 0 = no framebuffer node */
	const char *fb_format;
	const char *bootargs;
	uint64_t initrd_start, initrd_end;	/* end == start => none */
};

/* Copy `in` into out[outsize] and patch it. Returns 0 or a negative libfdt error. */
int fdt_patch(const void *in, void *out, int outsize, const struct patch_in *p);
