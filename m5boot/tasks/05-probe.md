# Task 05 — URGENT: first native result = reset loop. Build a diagnostic m5boot (probe) that can't loop

**NATIVE result (locally verified by the PM):** m5boot (sha256 039adce6…) was installed as the stub's boot object (stub LocalPolicy Permissive, `coih` set). On power-on the Mac **reset ~6 times**, then iBoot fell back to Recovery ("macOS needs to be reinstalled"). Whether any m5boot text appeared is being asked of the owner now.

**Leading hypothesis:** m5boot fails in step 1 (the boot_args layout differs on macOS 26 / mBoot-18000.161.10, i.e. H3/mem_actual), so it runs with no console, panics/halts before the step-2 WDT disable, and the WDT resets the Mac → loop. Also possible: an early exception before any console, or the 49 MB object size.

Build `build/m5boot-probe.bin` (separate target; keep the normal build intact). It **must not loop** and must show the maximum on screen in ONE boot:
1. **At entry, before any parsing:** disable the WDT with the single allowed write at the hard-coded PA `0x2_8836_C000 + 0x1c` (from our own ADT dump of this exact Mac; record the provenance). Read it back.
2. **Exception vectors:** install our own VBAR immediately, so any synchronous exception/SError paints a full-screen colour + ESR/ELR/FAR in hex, then halts (`wfe`). Never return to iBoot's vectors.
3. **Framebuffer without trusting the layout:** try the boot_args video fields under each candidate layout (608 / 1024 / any others the sources suggest). Use the first one that's plausible (inside DRAM per physBase/memSize, sane width/height/stride/depth, e.g. 3024x1964). Fallback for the probe only: `0x10bd3110000`, 3024x1964, 30 bpp (third-party reported, betizzel). Paint a **coloured bar per step**, so a photo shows how far it got even if the text fails.
4. **On screen, large font:** EL, SCTLR, CurrentEL, the image load address, boot_args raw hex (first 0x180 bytes), the decoded fields under each candidate layout, ADT pointer/len validity, and the WDT before/after values.
5. Run the normal steps 2–6 with on-screen status. Then **halt before jumping to Linux** and show "PROBE COMPLETE". The halt is the point: the owner photographs the screen, then holds power to return to macOS.
6. Keep the probe small: no kernel payload, so the build itself also tests the size hypothesis (if the probe shows text and the full build didn't, size/load is implicated).

Same hardware-safety rules: one WDT write, our RAM, the framebuffer. Host tests + QEMU VM run. Publish the SHA-256. End with `DONE 05`.
