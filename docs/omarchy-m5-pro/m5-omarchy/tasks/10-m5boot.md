# Task 10 — m5boot: our own clean-room boot object for J714s (no m1n1)

**Why:** the owner won't hand-build m1n1, and m1n1's notice (upstream /CLAUDE.md @ c9a03479) forbids AI use of it. That rules out AI-authored m1n1 builds the owner just "clicks". So we write our own minimal boot object that iBoot launches via `kmutil configure-boot --raw`, which boots our Linux directly.

**Hard provenance rule:** no m1n1 code, no m1n1-derived code (aura, aurora/edimoldovan/omacom m1n1 forks), no betizzel m1n1 patches, no m1n1 docs inside the m1n1 repo. Allowed sources (check AI instructions + license first, record them):
- Apple XNU open source: `pexpert/pexpert/arm64/boot.h` (boot_args), APSL.
- AsahiLinux/docs (the docs repo): boot process, ADT format, memory map.
- The Linux kernel: arm64 boot protocol, apple drivers (wdt, dart, simplefb, etc.).
- libfdt (BSD/GPL).
- Our own dumps.

Record every source in `reports/10-m5boot.md`.

**v0 scope (boot to a shell, single core):**
1. Entry from iBoot. Document what state iBoot leaves (EL, MMU/caches, x0 = boot_args, load address with `--entry-point 2048 --lowest-virtual-address 0`), citing sources. Handle both MMU-on and MMU-off safely, and clean caches before turning the MMU off.
2. Parse boot_args: physBase/memSize, video (base/stride/width/height/depth), the ADT pointer/length, and the cmdline.
3. Minimal ADT parser: get the memory-map carveouts from `/chosen/memory-map` (and anything else that must be reserved), plus the watchdog node.
4. Patch our embedded `t6050-j714s.dtb` with libfdt: `/memory`, `reserved-memory` for the carveouts, a `simple-framebuffer` node from boot_args video, `/chosen` bootargs, initrd start/end, `linux,initrd`, and the kaslr seed if trivial.
5. Disable the WDT (register layout from the Linux apple_wdt driver and our ADT `wdt` node).
6. A framebuffer text console (tiny 8x16 font) that prints each step, so a black-screen hang tells us where it stopped.
7. Payload: m5boot.bin = shim + DTB + **uncompressed** Image + initramfs, appended with a small header. Relocate the kernel to a 2 MiB-aligned address inside RAM, avoiding the carveouts, and jump with x0 = FDT (MMU off, D-cache clean, EL2 or EL1 per the arm64 boot protocol).
8. Size check: report the total boot object size. If we suspect a kmutil/iBoot size limit, research it (cite) and fall back to a loader-kernel design (shim + a small kernel that kexecs).

**Tests (label VM / host-only, never "native"):**
- Unit-test the FDT patching on the host with synthetic boot_args + a synthetic ADT built from our dump values.
- A QEMU aarch64 `virt` test of the jump path: fake boot_args, shim → our Image (or a tiny test kernel) → reaches early console.
- Report what can only be verified natively.

**Deliverables:** `m5boot/` source (license: MIT unless an input requires otherwise), `build/m5boot.bin` + SHA-256, `reports/10-m5boot.md` (design, sources/provenance, tests, native risks). Also: does betizzel's `finish-install.sh` accept a non-m1n1 binary as `--m1n1` (any m1n1-specific checks)? If it doesn't, write our own `tools/arm-stub.sh` doing the same (bless, app, `.IAPhysicalMedia`, step2 with `kmutil configure-boot -c m5boot.bin`) from Apple/Asahi-docs sources.
End with `DONE 10`. Task 09 continues/finishes first if it's close.

## Addendum (owner requirements, 2026-11-04 15:40)
- **Boot assumptions must be cited.** Every assumption about iBoot's hand-off state (EL, MMU/cache state, load/entry address, boot_args layout, what x0 holds, framebuffer state, the watchdog) needs a source quote + link in report 10. Unsourced = **HYPOTHESIS**, listed separately, with how the first native boot tests it.
- **Independent review:** after DONE 10, a separate reviewer session will review m5boot. Keep the code small, commented, and with no clever tricks.
- **Hardware-safety limits (hard rules for m5boot v0 and the first native boot):**
  - m5boot does no writes except: the WDT disable, its own RAM, and the framebuffer.
  - No PMGR/clock/power writes. No SMC writes. No NVMe/storage access. No NVRAM writes.
  - Kernel + DT for the first native boot: **no audio** (no codec/amp/speaker nodes or drivers. Speaker protection is unproven on T6050, so there's a damage risk). No SMC write paths (battery charge control, fans: leave the SMC alone). No GPU/DCP. No PMP writes. Our probe module stays read-only.
  - Audit `t6050-j714s.dts` and the kernel config against these rules. List what you disable.
- **Recovery for m5boot:**
  - A hang means hold power → Startup Options → Macintosh HD. That's macOS's own LocalPolicy, untouched.
  - To uninstall: delete the stub (08 §4).
  - State plainly that the DFU path is verified only as far as **device detection/identification**. A TSS signing check (`idevicerestore -t`) is planned. Revive/restore is untested.
