# Task 19 — gz10: disable the SECONDARY watchdog (third-party reported lead)

Source (third-party reported, Discord DM from betizzel's agent, 2026-11-04 23:23; describes m1n1 *behaviour* from their boot logs, not code — keep this provenance in NOTES):
[summary, third-party reported by betizzel's agent] their loader clears a second watchdog word at 0x288330008 on this wdt version, their logs show it disabled on every J714s boot, and they consider writing 0 there safe on J714s. They never read it before the clear. Regs 1-4 of /arm-io/wdt are single words in the always-on PMGR window 0x288300000.

gz10 = gz9 (exact same inputs/cmdline) +
1. At entry: read wdt reg[1..4] (only if runtime ADT reg[i] translates to exactly 0x2_8833_5260/0x2_8833_0008/0x2_8833_002C/0x2_8833_0020), twice ~1 s apart, print.
2. If ADT wdt-version is 2 or 3 and reg[2] translates to exactly 0x2_8833_0008: write 32-bit 0 there, read back, print. Repeat right before the jump. Never write reg 1/3/4.
3. Pass the before/after values to Linux so the logger records them: append `m5.wdt2=<before>,<after>` to the cmdline.
Owner-authorised exception to the WDT-only write rule: exactly this one register. Host + VM tests. NOTES entry with hash. Print exactly `DONE 19` (or `BLOCKED 19: <q>`). No dialogs.
