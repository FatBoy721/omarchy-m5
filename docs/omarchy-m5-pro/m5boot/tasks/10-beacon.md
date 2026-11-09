# Task 10 (URGENT): beacon probe, a screen-independent output channel (time-coded watchdog reset)

**NATIVE:** gz2 (sha df5f8d41) and probe2 both run (no iBoot panic, power stays on), but the screen stays **black**, even with the vram tiers. We can't tell whether the display isn't scanned out after the fuOS hand-off, or our code stops before painting. We need an output channel that doesn't depend on the screen.

Build `build/m5boot-beacon.bin` (same header: a branch at 0, 16 KiB padded):
1. Entry: VBAR, then the WDT disable (as now). Then run the probe logic, collecting a **result code**:
   - entry reached;
   - boot_args sane (revision/version known, physBase/memSize plausible);
   - which cmdline-length layout matched (none/608/1024/other);
   - ADT pointer valid + parsed;
   - /vram found in the runtime ADT;
   - the boot_args Video base inside /vram;
   - an exception taken (the VBAR handler also beacons).

   Pack this into a small integer (document the table in NOTES.md).
2. **Beacon:** re-arm the watchdog to bite after `T = 20 + 10*code` seconds (cap ~200 s), using the register sequence from Linux `drivers/watchdog/apple_wdt.c` (fetch it into ref/ if it isn't there; cite it). Writes are allowed only to the WDT block's registers that driver uses (timer, bite time, control) at the WDT PA `0x2_8836_C000`. Then `wfe`. When the WDT bites the Mac resets; the owner times power-on → reset.
   - Encode the most important facts in the first beacon. Optional: a second "digit" via a 2-phase scheme isn't possible, since one reset ends the run, so pick the encoding carefully. Prefer "furthest stage reached + layout matched".
3. Still attempt the screen paint (tier a/b/c) as well, in case the display works.
4. The exception handler beacons with a distinct code (for example code 15), so a crash is distinguishable.
5. Host tests for the code packing + the WDT register sequence (against a fake MMIO). QEMU: the fake WDT shows the right bite value. Publish the hash and the timing table. End with `DONE 10`.

## Addendum (PM, from ~/m5-omarchy/reports/20-fb-after-handoff.md, which you may read)
1. **Paint from boot_args Video at FIXED offsets** before any layout logic: base 0x28, rowBytes 0x38, width 0x40, height 0x48, depth 0x50. Only when sane: 3024x1964, stride 12096, inside DRAM.
2. **After every paint:** `dc civac` over the painted range + `dsb sy`. Our stores may be stuck in cache if the MMU/D-cache is on at entry. Read CurrentEL and the matching SCTLR M/C bits first.
3. **Beacon priority bits:** entry reached, MMU on at entry, D-cache on, boot_args video base == ADT vram base (0x105_D311_0000), video geometry sane, layout matched. Keep T = 20 + 10*code within ~200 s. If the bits do not fit, encode the 4 most important bits (16 values) and document it.
