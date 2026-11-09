/* Task 10 + addendum host test: 4-bit code packing (bit3 MMU, bit2 D-cache, bit1 Video base == vram base,
 * bit0 geometry 3024x1964/12096/30-32bpp), timing (20+10c, exception 10 s, all < 2^32 ticks at 24 MHz), the
 * fixed-offset FB DRAM bound, and the WDT register sequence against a fake MMIO block (only CUR/BITE/CTRL touched). */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "beacon.h"

int main(void)
{
	const uint64_t V = 0x105D3110000ULL;
	struct bootargs ba = { .v_base = V, .v_width = 3024, .v_height = 1964, .v_stride = 12096, .v_depth = 30 };
	assert(beacon_code(0, &ba, V) == 3);
	assert(beacon_code(1, &ba, V) == 11 && beacon_code(4, &ba, V) == 7 && beacon_code(5, &ba, V) == 15);
	assert(beacon_code(0, &ba, V + 0x1000) == 1);
	ba.v_depth = 0x1020; assert(beacon_code(0, &ba, V) == 3);	/* depth low byte 32, rotate bits ignored */
	ba.v_depth = 24; assert(beacon_code(0, &ba, V) == 2);
	ba.v_depth = 30; ba.v_stride = 3024 * 4 + 64; assert(beacon_code(0, &ba, V) == 2);
	ba.v_stride = 12096; ba.v_width = 3456; assert(beacon_code(0, &ba, V) == 2);
	ba.v_width = 3024;

	/* fixed-offset FB: needs sane geometry and the whole range inside DRAM */
	const uint64_t DB = 0x10000000000ULL, DS = 0x600000000ULL, SZ = 12096ULL * 1964;
	assert(beacon_fixed_fb(&ba, DB, DS) == V);
	ba.v_base = 0x10bd3110000ULL; assert(beacon_fixed_fb(&ba, DB, DS) == ~0ULL);	/* the G1 address */
	ba.v_base = DB + DS - SZ; assert(beacon_fixed_fb(&ba, DB, DS) == DB + DS - SZ);
	ba.v_base = DB + DS - SZ + 4; assert(beacon_fixed_fb(&ba, DB, DS) == ~0ULL);
	ba.v_base = DB - 4; assert(beacon_fixed_fb(&ba, DB, DS) == ~0ULL);
	ba.v_base = V; ba.v_height = 2000; assert(beacon_fixed_fb(&ba, DB, DS) == ~0ULL);

	for (int c = 0; c <= 15; c++) assert(beacon_seconds(c) == 20u + 10u * c);
	assert(beacon_seconds(16) == BEACON_EXC_SECONDS && beacon_seconds(-1) == BEACON_EXC_SECONDS);
	assert((uint64_t)WDT_RATE * 170 < (1ULL << 32));

	static uint32_t regs[0x1000], ref[0x1000];
	memset(regs, 0xa5, sizeof regs); memcpy(ref, regs, sizeof regs);
	wdt_beacon(regs, beacon_seconds(14));
	assert(regs[0x10 / 4] == 0 && regs[0x14 / 4] == 24000000u * 160 && regs[0x1c / 4] == 4);
	for (int i = 0; i < 0x1000; i++)
		if (i != 0x10 / 4 && i != 0x14 / 4 && i != 0x1c / 4) assert(regs[i] == ref[i]);
	wdt_beacon(regs, BEACON_EXC_SECONDS);
	assert(regs[0x14 / 4] == 24000000u * 10);
	/* beacon3: stage s -> 10 + 10s (0..16 -> 10..170), success 175, all < 2^32 ticks */
	for (uint32_t st = 0; st <= 16; st++) assert(beacon3_seconds(st, 0) == 10 + 10 * st);
	assert(beacon3_seconds(99, 0) == 170 && beacon3_seconds(3, 1) == 175);
	assert((uint64_t)WDT_RATE * 175 < (1ULL << 32));
	puts("test_beacon: ok");
	return 0;
}
