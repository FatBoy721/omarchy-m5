# Task 02 — Core: boot_args, ADT, FDT patching, payload, jump (from allowed sources)

Research the facts yourself from the allowed sources (XNU boot.h / device_tree.h / start.s, AsahiLinux/docs, Linux booting.rst, libfdt). When `spec/m5boot-spec.md` appears (another session is writing it), cross-check against it. Where the two disagree, record both and pick the conservative option. Hardware specifics for J714s (WDT address, carveouts) will come from the spec. Until then use runtime lookups from the ADT by name/compatible, never hard-coded addresses.

Implement in `src/`, with host unit tests in `tests/`:
1. **Entry state:** detect the current EL and MMU/cache state. If the MMU is on: clean + invalidate the D-cache to PoC, then turn the MMU and caches off (or stay identity-mapped if the sources show that's safe). Record every assumption in NOTES.md with its source or HYPOTHESIS.
2. **boot_args:** your own struct definitions from XNU boot.h (cite the revision/version fields; check the revision at runtime and print it). Get physBase, memSize, the top of kernel data, video base/stride/width/height/depth, the ADT pointer + length, and the cmdline.
3. **ADT parser:** walk nodes/properties (format from device_tree.h + Asahi docs). Look things up by path and compatible. Get the memory-map carveouts (`/chosen/memory-map` or whatever the sources say) and the watchdog node `reg` (address translation through parent `ranges` per the sources).
4. **FDT patching (libfdt):** our embedded DTB gets:
   - `/memory` from boot_args
   - `/reserved-memory` entries for every carveout + m5boot's own image
   - a `simple-framebuffer` node (reg, width, height, stride, format `a8r8g8b8` or `x8r8g8b8` per depth). Set `chosen/stdout-path` only if safe.
   - `/chosen`: bootargs (an embedded default plus the boot_args cmdline if it's set), `linux,initrd-start/end`
5. **WDT:** disable with the single register write from Linux `apple_wdt.c` (`apple_wdt_stop`), using the address from the ADT. Print before and after.
6. **Payload format:** a small header appended after the m5boot code (`magic, version, offsets/sizes for dtb, Image, initrd`) + a host tool `tools/mkpayload.py` that builds `m5boot.bin` from inputs listed in `spec/inputs.md` (until then, test inputs).
7. **Jump:** copy the Image to a 2 MiB-aligned address inside RAM, avoiding the carveouts/initrd/FDT, honoring the Image header's `text_offset`/`image_size` (booting.rst). Clean the D-cache to PoC, invalidate the I-cache, disable the MMU, then jump with x0 = FDT, x1–x3 = 0.
8. Framebuffer progress messages at every step (`[m5boot] step N: ...`) and an on-screen panic message with the step if anything fails, then halt (`wfe` loop).

**Tests:**
- Host: FDT patching with a synthetic boot_args + a synthetic ADT; payload round-trip.
- QEMU virt (label VM): m5boot with a fake boot_args/ADT in RAM → jumps into a real arm64 Linux Image (any test Image, or ours from inputs.md once available) → earlycon output.

End with `DONE 02`.
