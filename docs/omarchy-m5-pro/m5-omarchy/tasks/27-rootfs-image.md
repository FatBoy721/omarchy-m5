# Task 27 — Omarchy rootfs onto disk0s5 WITHOUT USB (written from macOS), + switch_root

USB/SSH into native Linux is blocked (ATC0 needs PMP). macOS can write raw to /dev/rdisk0s5. Plan: you build an image, PM dd's it from macOS.

Target facts: disk0s5 = GPT "Linux filesystem", exactly 120,000,000,000 bytes, 4096-byte logical blocks, currently zero except a possible `M5LOG` text header in its first 4 MiB (raw logger channel, task 18 in ~/m5boot).

1. Build `build/rootfs-omarchy.ext4` from build/rootfs-omarchy.tar.zst (sha f9be6781…): ext4, block size 4096, label `omarchy`, size = content + 4 GiB slack (sparse); first boot runs resize2fs to grow to the full partition. Ship `build/rootfs-omarchy.ext4.zst` + sha256 of both. Use all 24 cores.
2. In the rootfs: autologin user on tty1 straight into Hyprland (Omarchy session) with software rendering (simpledrm + pixman/llvmpipe; no GPU). journald persistent, plus a unit that copies `journalctl -b` and dmesg to the ESP (disk0s4, FAT32, verified-mount like the task-18 logger) every 30 s, so a desktop failure is readable from macOS.
3. Initramfs: new cmdline `m5.root=s5` → after the logger starts, find the partition with GPT Linux-fs type and size exactly 120,000,000,000, check ext4 label `omarchy`, mount it and switch_root to /sbin/init. Refuse otherwise and stay in the initramfs shell (logged). Keep the raw-s5 logger channel OFF when m5.root=s5 is set (it would clobber the fs).
4. Keyboard/trackpad: check our kernel has the dockchannel/MTP HID transport (betizzel patch 0005) and what it needs at runtime (firmware?). Report what will/won't work.
5. VM-test the whole path (qemu NVMe 4K blocks, same GPT layout) to a Hyprland session (screenshot). Report: reports/27-rootfs-image.md with exact macOS write command for the PM. Do NOT touch the Mac.
Print exactly `DONE 27` (or `BLOCKED 27: <q>`). No dialogs.
