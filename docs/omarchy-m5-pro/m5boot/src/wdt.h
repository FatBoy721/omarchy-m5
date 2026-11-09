#pragma once
#include "util.h"
#define WDT_CTRL_RESET_EN 4u
struct wdt_snap { uint32_t cur[3], bite[3], ctrl[3], bark0; };
/* Read WD0..WD2 CUR/BITE/CTRL + WD0 BARK (reads only). */
void wdt_read(volatile uint32_t *base, struct wdt_snap *s);
/* Write 0 to every WDi_CTRL that reads RESET_EN set; re-read into *after. Returns how many were disabled. */
int wdt_disable_armed(volatile uint32_t *base, struct wdt_snap *after);
/* The four extra single registers of the ADT wdt node (reg[1..4]); our dump's values, read-only. */
#define WDT_EXTRA_N 4
#ifndef WDT_EXTRA_PAS	/* the VM build overrides these (Makefile D_vmgz7) */
#define WDT_EXTRA_PAS { 0x288335260ULL, 0x288330008ULL, 0x28833002cULL, 0x288330020ULL }
#endif
