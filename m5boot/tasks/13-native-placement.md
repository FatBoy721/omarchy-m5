# Task 13 (URGENT): NATIVE gz3 console. Fix "no room to inflate Image.gz"

**NATIVE (owner photo `spec/native-gz3-screen.jpg`, gz3 f689052a):** the m5boot text console works on the real Mac. Transcribed:
- step 1: entry x0=0x100065bc000, **EL2**, SCTLR=0x30000180 (MMU/caches off).
- boot_args **rev 3 ver 2 (UNKNOWN revision)**; BOOT_LINE_LENGTH=1024 is the plausible layout.
- virtBase 0x15ae4000, **physBase 0x10003ae4000, memSize 0x5c701c000, topOfKernelData 0x100065cc000, memSizeActual 0x600000000**, flags 0.
- video 0x105d3110000, 3024x1964, stride 12096, depth 0x1001e. cmdline "".
- ADT ptr 0x17884000 → PA 0x10005884000, len 737280, parsed. /vram reg 0x105d3110000 +0x57ac000. WDT verified, disabled.
- step 3: `/chosen/memory-map: 9 ranges (63 skipped: not 16 bytes or base+size overflows)`, `/chosen/carveout-memory-map: 164 ranges (165 skipped)`.
- step 4: payload dtb 65890, Image.gz 3105641 (text_offset 0 image_size 0 flags 0), initrd 2143952.
- **PROBE HALTED in step 4: no room to inflate Image.gz.**

Do:
1. Reproduce **on the host**: build a synthetic boot_args + ADT with exactly these values, plus the real `/chosen/memory-map` and `/chosen/carveout-memory-map` property sets from our ADT dump (`~/m5-omarchy/reports/04-j714s-full.txt`, which you may read for these two nodes). Run `place()` / the inflate-scratch placement and find why no hole is found in ~23 GB.
   - Suspects: the window bounds; a bogus huge range from a mis-parsed entry (the "skipped" counts suggest the format differs: the values may be 16 bytes = base+size, but names/encoding vary); the ISIZE/image_size used for sizing (image_size 0 printed before inflate); alignment.
2. Also check the "skipped" logic: what are the 63 / 165 skipped entries? (E.g. zero-size placeholders are fine to skip, but make sure no real reservation is dropped.)
3. Fix it. Add the native values as a regression host test. Rebuild **gz4** (same header/early code) and publish the hash. Bonus: print the chosen inflate/kernel/FDT/initrd addresses on screen before the countdown.

End with `DONE 13`.
