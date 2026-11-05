# Task 18 — native logging that needs NO camera (owner: no more photos/video)

gz8 native run: Linux ran (install marker consumed) but /m5log on the ESP was never created. Cause unknown. The owner will not photograph screens again; every native result must land on disk.

Mac disk facts (read-only from macOS, 22:53):
- disk0s4: GPT type EFI, FAT32 (made by macOS), 499,998,720 B, **4096-byte logical blocks**, empty.
- disk0s5: GPT type Linux filesystem, 120,000,000,000 B, 4096-byte blocks, **first 4 MiB all zero** (ours, reserved for rootfs).
- Same NVMe; other partitions are Apple (APFS ISC, APFS 868 GB, APFS stub 6 GB, APFS recovery) — never touch.

Build a new initramfs (+ kernel config changes if needed) for gz9:
1. Find why m5-esplog wrote nothing. Check: vfat + nls_cp437 + nls_iso8859_1 built-in? FAT on 4K logical sectors? nvme_apple builds nvme0n1? busybox can read GPT type GUIDs/sizes? Fix all you find. Reproduce in QEMU with an NVMe disk using 4096-byte logical blocks and this exact GPT layout/types/sizes (sparse image).
2. Add channel 2 (raw, no filesystem): write the log as plain text to the start of disk0s5, max 4 MiB, header `M5LOG v1 boot=<n> uptime=<s>`. Pick the partition only if: GPT type = Linux filesystem, size == 120,000,000,000, and its first 4 MiB are all zero OR start with `M5LOG`. Otherwise refuse. O_DIRECT/sync each write.
3. Start logging as EARLY as possible (as soon as nvme0n1 appears), then every 5 s. Log: full dmesg, /proc/interrupts, uptime, what the logger itself saw (devices, errors) — so a failure of the logger is itself logged where possible (channel 2 first).
4. Also log to the m5fb earlycon what the logger does, every step.
5. Tell me the exact macOS read commands. Put artifacts + hashes in ~/m5boot/spec/inputs.md § Slim v4-log and rebuild m5boot as gz9 = gz8 + this initramfs (+kernel if changed). Same tests. NOTES.md entry.
Print exactly `DONE 18` (or `BLOCKED 18: <q>`). No dialogs.
