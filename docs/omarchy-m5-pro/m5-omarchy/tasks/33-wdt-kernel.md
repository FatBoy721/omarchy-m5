# Task 33 — watchdog in every kernel/DT from now on (unblocks gz15 hands-free loop)
PM decision for m5boot BLOCKED 24: option A.
1. Kernel "loop-v1" = input-v2 kernel (patches 0002/0003) + CONFIG_APPLE_WATCHDOG=y + CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y (+ WATCHDOG_CORE). Keep m5_pmgr_ro etc.
2. DTB I3-wdt = I3 + the wdt node (0x2_8836_C000 block, apple,t6050-wdt) ENABLED. Check apple_wdt.c: what it does at probe (does it stop/keep a running WD1?), its max timeout on 24 MHz, its restart handler (writes WD1 for an immediate reset). Cite lines.
3. Rootfs drop-in (for m5drop/, not a new image): /etc/systemd/system.conf.d/m5-watchdog.conf with RuntimeWatchdogSec=60 RebootWatchdogSec=60 — so a frozen desktop resets the Mac.
4. Hand the implementer: the busybox `watchdog` applet must run in the loader/test initramfs (`watchdog -t 10 -T 60 /dev/watchdog`) from the moment /dev/watchdog exists until switch_root (systemd takes over).
Hashes → ~/m5boot/spec/inputs.md § Loop v1 (new filenames). Report reports/33-wdt-kernel.md. Print exactly `DONE 33` (or `BLOCKED 33: <q>`). No dialogs.
