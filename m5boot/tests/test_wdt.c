/* Task 16 host test: fake WDT block (0x4000 bytes). wdt_read picks WD0/1/2 CUR/BITE/CTRL + WD0 BARK at the
 * apple_wdt.c offsets; wdt_disable_armed writes 0 ONLY to CTRLs with RESET_EN set and touches nothing else. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "wdt.h"

int main(void)
{
	static uint32_t r[0x1000], ref[0x1000];
	for (int i = 0; i < 0x1000; i++) r[i] = 0xa5a50000u | i;
	r[0x0c / 4] = 4 | 1;	/* WD0: RESET_EN + IRQ_EN -> disabled */
	r[0x1c / 4] = 0;	/* WD1 already off -> not written */
	r[0x2c / 4] = 4;	/* WD2 armed -> disabled */
	memcpy(ref, r, sizeof r);
	struct wdt_snap s, a;
	wdt_read(r, &s);
	assert(s.cur[0] == ref[0] && s.bite[1] == ref[0x14 / 4] && s.ctrl[2] == 4 && s.bark0 == ref[0x08 / 4]);
	assert(wdt_disable_armed(r, &a) == 2);
	assert(a.ctrl[0] == 0 && a.ctrl[1] == 0 && a.ctrl[2] == 0);
	for (int i = 0; i < 0x1000; i++)
		if (i != 0x0c / 4 && i != 0x2c / 4) assert(r[i] == ref[i]);	/* nothing else written (incl. WD1_CTRL) */
	assert(wdt_disable_armed(r, &a) == 0);	/* idempotent */
	r[0x1c / 4] = 0x2;	/* IRQ_STATUS only, no RESET_EN: left alone */
	assert(wdt_disable_armed(r, &a) == 0 && r[0x1c / 4] == 2);
	puts("test_wdt: ok");
	return 0;
}
