#pragma once
#include "probefb.h"
#include <string.h>
#define BEACON_EXC_SECONDS 10	/* exception: below every data code (20..170 s) */
#define WDT_RATE 24000000u	/* J714s DTB clkref (see beacon.c) */
int beacon_geom(const struct bootargs *ba);
uint64_t beacon_fixed_fb(const struct bootargs *ba, uint64_t dbase, uint64_t dsize);
int beacon_code(uint64_t sctlr, const struct bootargs *ba, uint64_t vram_base);
uint32_t beacon_seconds(int code);
void wdt_beacon(volatile uint32_t *wdt, uint32_t seconds);
#define BEACON3_OK_SECONDS 175	/* 175 * 24e6 < 2^32 */
uint32_t beacon3_seconds(uint32_t stage, int success);
