/* Task 13 regression (NATIVE gz3, spec/native-gz3-screen.jpg): physBase 0x10003ae4000, memSize 0x5c701c000,
 * topOfKernelData 0x100065cc000, x0 0x100065bc000, ADT PA 0x10005884000 len 737280, FB 0x105d3110000 3024x1964.
 * Carveouts = tests/native-j714s-carveouts.txt (our ADT dump). Without drop_ram_window the inflate scratch can't be
 * placed (the gz3 halt); with it, the main.c placement sequence succeeds, inside the window, overlapping nothing. */
#include <assert.h>
#include <stdio.h>
#include "place.h"

#define MAXR 528
static struct range rsv[MAXR], avoid[MAXR];

static int load(const char *path)
{
	FILE *f = fopen(path, "r"); assert(f);
	char line[256]; int n = 0;
	unsigned long long b, s;
	while (fgets(line, sizeof line, f))
		if (line[0] != '#' && sscanf(line, "%llx %llx", &b, &s) == 2) { rsv[n].base = b; rsv[n].size = s; n++; }
	fclose(f);
	return n;
}

static int run(int n, int drop, uint64_t out[4])
{
	const uint64_t PH = 0x10003ae4000ULL, MS = 0x5c701c000ULL, TOP = 0x100065cc000ULL;
	int na = n, d;
	if (drop) na = drop_ram_window(rsv, n, PH, MS, &d);
	struct range win = { align_up(TOP, 2 << 20), 0 };
	win.size = align_down(PH + MS, 2 << 20) - win.base;
	for (int i = 0; i < na; i++) avoid[i] = rsv[i];
	avoid[na++] = (struct range){ 0x105d3110000ULL, align_up(12096ULL * 1964, 1 << 14) };	/* FB */
	avoid[na++] = (struct range){ 0x100065bc000ULL & ~0x3fffULL, 0x4000 };			/* boot_args */
	avoid[na++] = (struct range){ 0x10005884000ULL, 737280 };				/* ADT */
	int fixed = na;
	/* main.c order: inflate scratch (slim ISIZE), kernel (image_size 0 -> 64M headroom guess), FDT 2M, initrd */
	uint64_t sizes[4] = { 7907336, 0x80000 + align_up(7907336, 1 << 21) + (64ULL << 20), 2 << 20, 2143952 };
	uint64_t aligns[4] = { 2 << 20, 2 << 20, 2 << 20, 1 << 16 };
	for (int i = 0; i < 4; i++)
		if (place(win, avoid, &na, MAXR, sizes[i], aligns[i], &out[i])) return -1;
	for (int i = 0; i < 4; i++) {	/* inside the window, and overlapping no reservation or earlier placement */
		assert(out[i] >= win.base && out[i] + sizes[i] <= win.base + win.size);
		for (int j = 0; j < fixed; j++) assert(out[i] + sizes[i] <= avoid[j].base || avoid[j].base + avoid[j].size <= out[i]);
		for (int j = 0; j < i; j++) assert(out[i] + sizes[i] <= out[j] || out[j] + sizes[j] <= out[i]);
	}
	return 0;
}

int main(int argc, char **argv)
{
	int n = load(argc > 1 ? argv[1] : "tests/native-j714s-carveouts.txt");
	assert(n == 89);	/* the dump's 16-byte carveouts (its 91 one-byte props are flags, correctly skipped) */
	uint64_t out[4];
	assert(run(n, 0, out) == -1);	/* reproduces the native halt */
	assert(run(n, 1, out) == 0);
	printf("test_native13: ok (scratch %llx kernel %llx fdt %llx initrd %llx)\n",
	       (unsigned long long)out[0], (unsigned long long)out[1], (unsigned long long)out[2], (unsigned long long)out[3]);
	/* drop only exact matches */
	struct range r[3] = { { 0x1000, 0x2000 }, { 0x1000, 0x1fff }, { 0x1000, 0x2000 } };
	int d; assert(drop_ram_window(r, 3, 0x1000, 0x2000, &d) == 1 && d == 2 && r[0].size == 0x1fff);
	return 0;
}
