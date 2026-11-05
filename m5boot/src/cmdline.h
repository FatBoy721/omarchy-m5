#pragma once
#include "util.h"
/* Build the gz5+ kernel command line into buf (see cmdline.c). xoff 0 = no x-offset field; extra may be NULL.
 * Returns its length, or -1 if it doesn't fit. */
int build_cmdline(char *buf, size_t n, const char *base, const char *iboot,
		  uint64_t fb, uint32_t w, uint32_t h, uint32_t stride, uint32_t bpp, uint32_t xoff, const char *extra);
