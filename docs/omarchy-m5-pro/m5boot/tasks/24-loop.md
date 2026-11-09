# Task 24 — hands-free test loop (owner: no more full rebuilds / 1TR per test)

Goal: after ONE more 1TR install, every kernel/DT/initramfs/rootfs-tweak test runs with zero owner action:
PM (over SSH to macOS) copies files to the ESP (disk0s4, FAT32) → `bless --nextonly` the Omarchy stub → `shutdown -r now` → m5boot (unchanged) → loader kernel → reads ESP → kexec into the test kernel → test runs, logs to ESP → after a timeout the Mac reboots itself → macOS (still the default) → PM reads logs.

Build:
1. Loader initramfs (busybox + kexec-tools, static; we already have a loader variant in ~/m5-omarchy/tools/initramfs) with init logic: run the existing v4 logger; mount ESP (verified-mount rule); if ESP `m5next/` has Image + dtb + initrd + cmdline (+ a sha256 file that matches), log and `kexec -l … && kexec -e`; else boot the built-in default (m5.root=s5 Omarchy). Consume-once: rename m5next→m5last before kexec so a bad build can't loop.
2. Rootfs drop-ins: before switch_root, copy ESP `m5drop/` into the new root (allow-list: /etc, /usr/local, /usr/lib/systemd, /usr/lib/firmware; log every file). So rootfs tweaks never need a 19 GB rewrite.
3. Auto-return to macOS: a kernel `m5.autoreboot=<s>`: after <s> seconds (logs flushed + ESP unmounted) reboot. Mechanism must actually reset this Mac: apple_wdt restart (CONFIG_APPLE_WATCHDOG=y; m5boot disables WD1 but Linux can re-arm it) — or leave the secondary wdt (0x2_8833_0008, resets at ~80 s, NATIVE-observed) armed when m5.autoreboot is set and m5boot sees a flag? Pick the safest, cite. Default macOS must be what boots after the reset (verify the reasoning: stub won't be default because PM uses bless --nextonly).
4. kexec on this SoC: check the kernel has KEXEC + the arm64 bits; devices (NVMe ANS, DARTs, earlycon fb) must survive or be shut down cleanly — cite kernel behaviour; VM-test the full chain (loader → kexec → test kernel → autoreboot).
5. gz15 = gz14 code with the loader kernel+initramfs. NOTES + hash. Write tools/loop/push-test.sh for the PM (macOS-side commands: mount ESP rw, copy m5next/m5drop, sha check, unmount, bless --nextonly via the stub, reboot) — PM runs it, not you.
Print exactly `DONE 24` (or `BLOCKED 24: <q>`). No dialogs. Do not touch the Mac.
