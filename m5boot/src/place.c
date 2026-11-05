#include "place.h"

/* NATIVE task 13: on J714s the carveout-memory-map contains the kernel's own RAM window (region-id-24 =
 * [physBase, physBase+memSize), exactly). That entry is the RAM we're given, not a reservation; keeping it blocks
 * every hole (gz3 halted "no room to inflate") and would mark all RAM no-map in the FDT. Remove entries EXACTLY
 * equal to the window (conservative: anything else stays reserved). Returns the new count; *dropped = removed. */
int drop_ram_window(struct range *r, int n, uint64_t phys, uint64_t size, int *dropped)
{
	int o = 0;
	*dropped = 0;
	for (int i = 0; i < n; i++) {
		if (r[i].base == phys && r[i].size == size) { (*dropped)++; continue; }
		r[o++] = r[i];
	}
	return o;
}

int place(struct range win, struct range *avoid, int *n, int max, uint64_t size, uint64_t align, uint64_t *out)
{
	if (*n >= max || !size) return -1;
	if (win.base + win.size < win.base || win.base > ~0ULL - align) return -1;
	uint64_t x = align_up(win.base, align), end = win.base + win.size;
	for (int moved = 1; moved;) {	/* ponytail: O(n^2) rescan, n is a few hundred */
		moved = 0;
		if (x < win.base || x + size > end || x + size < x) return -1;
		for (int i = 0; i < *n; i++) {
			uint64_t e = avoid[i].base + avoid[i].size;
			if (e < avoid[i].base) e = ~0ULL;	/* overflowing range: treat as reaching the top */
			if (x < e && avoid[i].base < x + size) {
				if (e > ~0ULL - align) return -1;
				x = align_up(e, align);
				moved = 1;
				break;
			}
		}
	}
	avoid[*n].base = x; avoid[*n].size = size; (*n)++;
	*out = x;
	return 0;
}
