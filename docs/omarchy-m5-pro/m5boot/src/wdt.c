/* Task 16 (gz7): find and disable every watchdog in the J714s WDT block.
 * Layout = Linux drivers/watchdog/apple_wdt.c (GPL-2.0-only OR MIT, ref/linux/apple_wdt.c): "This HW block has
 * three separate watchdogs. WD0 resets the machine to recovery mode ... WD1 and WD2 trigger a normal machine
 * reset." WDx_CUR_TIME / BITE_TIME / CTRL at 0x00/0x04/0x0c, 0x10/0x14/0x1c, 0x20/0x24/0x2c; WD0_BARK_TIME 0x08.
 * "Whenever APPLE_WDT_CTRL_RESET_EN is set in APPLE_WDT_WDx_CTRL and CUR_TIME >= BITE_TIME the entire machine
 * is reset." CTRL_RESET_EN = BIT(2).
 * Owner-authorised (task 16) beyond the CLAUDE.md WD1-only rule: a 0 is written to WD0/WD2 CTRL too, but only
 * when that CTRL reads RESET_EN set, and only inside the main block. */
#include "wdt.h"

static const uint16_t cur_off[3] = { 0x00, 0x10, 0x20 }, bite_off[3] = { 0x04, 0x14, 0x24 }, ctrl_off[3] = { 0x0c, 0x1c, 0x2c };

void wdt_read(volatile uint32_t *base, struct wdt_snap *s)
{
	for (int i = 0; i < 3; i++) {
		s->cur[i] = base[cur_off[i] / 4];
		s->bite[i] = base[bite_off[i] / 4];
		s->ctrl[i] = base[ctrl_off[i] / 4];
	}
	s->bark0 = base[0x08 / 4];
}

int wdt_disable_armed(volatile uint32_t *base, struct wdt_snap *after)
{
	int n = 0;
	for (int i = 0; i < 3; i++)
		if (base[ctrl_off[i] / 4] & WDT_CTRL_RESET_EN) {
			base[ctrl_off[i] / 4] = 0;	/* apple_wdt_stop() equivalent for WDi */
			n++;
		}
#ifndef HOST
	__asm__ volatile("dsb sy" ::: "memory");
#endif
	wdt_read(base, after);
	return n;
}
