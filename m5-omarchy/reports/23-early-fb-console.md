# 23 — Early framebuffer console for the slim kernel (VM-tested; NATIVE pending)

## What was built
- **`earlycon=m5fb,<base>,<w>,<h>,<stride>,<bpp>`**: a new 150-line GPL driver `drivers/firmware/m5fb_earlycon.c`, adapted from `drivers/firmware/efi/earlycon.c`. Our patch is `tools/kernel/patches/0001-m5fb-earlycon.patch` (driver + `Kconfig.m5` + Makefile line + a `pr_notice("m5: setup_arch reached, earlycon parsed")` right after `parse_early_param()` in `setup_arch`).
  - bpp 30 = x2r10g10b10, white 0x3fffffff; bpp 32 = xrgb8888.
  - Before ioremap works, each scanline is mapped with `early_ioremap` (device memory). We can't use `early_memremap_prot`: it only exists with EFI (`ARCH_USE_MEMREMAP_PROT` is selected by EFI). Stores are aligned `writel_relaxed`, and clears use `memset_io`, because a plain memset may use DC ZVA, which faults on device memory.
  - From early_initcall on, the whole FB is mapped with `ioremap_wc`, as efifb does.
  - ponytail: **wraps to the top instead of scrolling**, because scrolling 23 MB of uncached FB per line is far too slow with initcall_debug. The two rows below the cursor are cleared, so the newest text sits just above a blank band.
  - Bug found in VM and fixed: `register_earlycon()` passes `opt = NULL` when the address parses, so the geometry must be read from `device->options`.
- **Failures stay on screen:**
  - `CONFIG_PANIC_TIMEOUT=0` (it was already 0 in slim), plus `panic=0` on the cmdline. arm64 has no CMDLINE_EXTEND: a built-in CONFIG_CMDLINE is ignored when the bootloader passes bootargs, so m5boot must pass it.
  - `PANIC_ON_OOPS` is off. `APPLE_WATCHDOG` is off, and `WATCHDOG_HANDLE_BOOT_ENABLED` is off.
- `CONFIG_KALLSYMS=y`, so initcall_debug and oopses show function names.
- Build: `tools/build-slim.sh` (applies our patches idempotently, asserts the key config symbols). Image 8433672 B, Image.gz **3378711 B** (sha256 in `~/m5boot/spec/inputs.md` § Slim kernel v2).

## VM test (QEMU virt, -cpu max, 16K pages)
- Cmdline: `mem=1G earlycon=m5fb,0x90000000,3024,1964,12096,30 keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8`. The FB is guest RAM above `mem=`, dumped with `pmemsave` and rendered (`build/t23/fb*.png`).
- Result: full text in x2r10g10b10 (227k white pixels, no other values), initcalls with symbol names, wrap-around working, and the expected final `Kernel panic - not syncing: VFS: Unable to mount root fs` (no root/initrd in this test) staying on screen. The kernel then idles in panic()'s loop and doesn't reboot.

## The reboot seen on gz4 [HYPOTHESIS]
With PANIC_TIMEOUT=0 and no `panic=` in gz4's bootargs, **a kernel panic would have hung, not rebooted**. So the reboot "some seconds later" was most likely **a hardware watchdog still armed**:
- either m5boot's WDT disable didn't take, or a different WDT instance or a later re-arm is involved;
- the old slim config had `APPLE_WATCHDOG=y`, but with `WATCHDOG_HANDLE_BOOT_ENABLED` unset the driver only marks a running WDT and never pings it (`apple_wdt_probe`: reads WD1_CTRL, sets WDOG_HW_RUNNING; no write);
- a hardware-level reset (SError/fatal async abort) is the alternative.

With m5fb on, the next run tells them apart: text that stops mid-stream **without** a panic or oops message, followed by a reboot, means the watchdog. If so, m5boot should read back `WD1_CTRL` after disabling it and print the value. A fallback is `APPLE_WATCHDOG=y` + `WATCHDOG_HANDLE_BOOT_ENABLED=y`, so the kernel keeps pinging it.

## For m5boot (PM)
Pass exactly (FB values from m5boot's runtime FB; base in hex, stride in bytes):
```
earlycon=m5fb,<base>,<width>,<height>,<stride>,30 keep_bootcon panic=0 initcall_debug ignore_loglevel loglevel=8 maxcpus=1 console=tty0 pd_ignore_unused clk_ignore_unused no_console_suspend nvme_apple.flush_interval=0
```
- Nothing shows before `parse_early_param()`. If the screen keeps m5boot's text, Linux died in head.S or early setup_arch (before earlycon).
- The first lines drawn are the replayed log from "Booting Linux on physical CPU".
