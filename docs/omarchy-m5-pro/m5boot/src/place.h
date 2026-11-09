#pragma once
#include "util.h"
/* Lowest `align`-aligned [x, x+size) inside win that overlaps none of avoid[0..*n).
 * On success appends it to avoid (capacity max) and returns 0. */
int place(struct range win, struct range *avoid, int *n, int max, uint64_t size, uint64_t align, uint64_t *out);
/* Drop ranges exactly equal to [phys, phys+size) (the kernel RAM window listed as a carveout). Returns new count. */
int drop_ram_window(struct range *r, int n, uint64_t phys, uint64_t size, int *dropped);
