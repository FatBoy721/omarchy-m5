# Task 16 (URGENT): gz7, find and disable the watchdog that resets us

**NATIVE (gz6 21d62e37, video frames spec/native-gz6-f06/f12/f14.jpg):** Linux ran ~45 s: initcalls, PMGR (some domains `PS b2bd_afc_0/1, b2bd_afr_0/3: Failed to reach power state 0xf`), the USB0 DART probe failed -110, deferred probe timeouts, `sync_state() pending …`, then a cursor. The screen was **stable/idle** when the Mac **reset** (no panic; panic=0; apple_wdt off). gz4 reset too. Leading hypothesis: **another watchdog is armed** (we only clear WD1_CTRL at +0x1c).

Our ADT dump (`~/m5-omarchy/reports/04-j714s-full.txt`), wdt@8836C000: compatible `wdt,t8101`, **wdt-version 3**, `simple-reconfig-wdog-support`, `simple-reconfig-wdog-icc-time` = 5, `trigger-config`, `panic-forcepoweroff-flag-bit`. **reg** has 5 entries: `0x2_8836_C000 +0x4000` (main block), `0x2_8833_5260 +4`, `0x2_8833_0008 +4`, `0x2_8833_002C +4`, `0x2_8833_0020 +4`.

gz7 (same everything else as gz6):
1. Step 2: **read and print** every 32-bit register in the main block that Linux `drivers/watchdog/apple_wdt.c` (fetch into ref/, cite it) or the ADT implies is a watchdog timer/bite/ctrl (WD0, WD1, any WD2 at the analogous offsets), plus the four extra single registers (read-only).
2. **Disable**: write 0 to the CTRL register of every watchdog **inside the main block** that reads reset-enabled (the bit Linux uses), with read-back + print. **Do NOT write the four extra registers** (unknown semantics: report their values only).
3. Right before the jump, re-read and print all of them again (and re-disable inside the block if anything re-armed).
4. Host test with a fake block. Publish the hash. End with DONE 16.
