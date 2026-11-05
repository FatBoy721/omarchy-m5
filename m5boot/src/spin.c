/* build/m5boot-spin.bin (task 05/06/09): start.S PROBE entry (VBAR + the one WDT write), then fill the FB one
 * solid colour ONLY at a vram-bounded selection (src/probefb.c tiers a/b/c). Otherwise silent. Then wfe forever. */
#include "probefb.h"

void __attribute__((noreturn)) probe_exception(void) { for (;;) __asm__ volatile("wfe"); }

void main(uint64_t x0)
{
	struct bootargs ba;
	struct fbsel s;
	bootargs_parse((const void *)x0, &ba);
	if (!probe_fb(&ba, &s))
		for (uint64_t y = 0; y < s.h; y++)
			for (uint64_t x = 0; x < s.w; x++)
				((volatile uint32_t *)(s.pa + y * s.stride))[x] = 0x3ff003ff;
	for (;;) __asm__ volatile("wfe");
}
