# Hands-free test loop: switching the M5 Pro between macOS and Omarchy over SSH

Since 2026-11-05 02:30 the Mac boots test builds of Omarchy and returns to macOS **with nobody touching it** (NATIVE).

## How it works
1. **One-time install** (needs a human, Apple rule): the boot object `gz16` is installed into the Omarchy stub from paired 1TR. It contains m5boot + a small *loader* Linux kernel/initramfs.
2. **macOS stays the default startup disk.** For each test, from another machine over SSH to macOS:
   - copy the test (kernel `Image`, `initrd`, `cmdline`, or rootfs drop-ins) to the FAT ESP (`m5next/`, `m5drop/`), with SHA-256 sums;
   - `bless --mount /Volumes/Omarchy --setBoot --nextonly` (one-shot boot into Omarchy);
   - `shutdown -r now`.
3. **On the Mac:** iBoot → m5boot → loader. The loader verifies hashes, consumes `m5next/` (so a bad build can't loop), and `kexec`s into the test kernel. Drop-ins are copied into the Omarchy root before `switch_root`.
4. **Getting back to macOS by itself:**
   - `m5.autoreboot=<s>`: the test reboots itself via the Apple watchdog driver's restart handler;
   - a **guard** service reboots any Omarchy session after 15 min unless an `m5stay` file is on the ESP (NATIVE: fired at 925 s);
   - a **hardware watchdog** (WD1, 60 s, petted by busybox `watchdog` then systemd `RuntimeWatchdogSec`) resets the Mac on any hang;
   - because the boot was one-shot, every reset lands back in macOS.
5. Logs are written by Linux to the ESP (fsynced) and read from macOS.

## Things we had to find out (NATIVE)
- kexec failed with `EBUSY`: our DT starts secondary CPUs with `spin-table`, so arm64 refuses kexec (`cpus_are_stuck_in_kernel()`); `nr_cpus=1` on the loader fixes it (gz16).
- FileVault must be off for unattended loops (otherwise the Mac waits at the unlock screen after a reset).
- A failed kexec must reboot, never fall back to a desktop that doesn't return (we learned this the hard way).
