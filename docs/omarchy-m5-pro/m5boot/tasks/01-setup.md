# Task 01 — Setup: allowed sources, toolchain, skeleton (spec arrives later in spec/)

1. **Fetch allowed sources** into `ref/` (gitignored). Before using each one, check its license and any CLAUDE.md/AGENTS.md/GEMINI.md, and record both in `NOTES.md`:
   - apple-oss-distributions/xnu: `pexpert/pexpert/arm64/boot.h`, `pexpert/pexpert/device_tree.h`, `osfmk/arm64/start.s` (for reference on how XNU consumes boot_args)
   - AsahiLinux/docs (the docs repo only)
   - the dtc repo for libfdt
   - the Linux docs `Documentation/arch/arm64/booting.rst` and `drivers/watchdog/apple_wdt.c`
2. **Toolchain** (user-level on this machine): freestanding aarch64 with clang `--target=aarch64-none-elf` + ld.lld, no libc. Vendor libfdt (BSD-2-Clause option) into `src/libfdt/`.
3. **Skeleton** in `src/`:
   - `start.S` entry stub: entry at offset 2048 per `kmutil --entry-point 2048`. Save x0, set up a stack, clear .bss, call `main(boot_args)`. Leave MMU/cache handling as clearly marked TODOs until the spec lands.
   - linker script, Makefile, `fb.c` (8x16 bitmap font text console on a linear 32bpp framebuffer)
   - `main.c` that prints "m5boot v0" and halts
   - a host-side test harness (`tests/`, built with the native compiler) for the pure-C parts
4. **QEMU smoke:** boot the skeleton under `qemu-system-aarch64 -M virt` with a fake framebuffer region, where feasible. Label it VM.

Don't implement the boot_args/ADT/FDT/jump logic until `spec/m5boot-spec.md` exists. When setup is done and the spec isn't there yet, end with `DONE 01`.
