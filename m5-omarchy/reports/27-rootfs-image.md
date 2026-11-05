# 27 — Omarchy rootfs on disk0s5 without USB, + switch_root (VM: boots to Hyprland; NATIVE pending)

**Result (VM):** QEMU virt, NVMe with **4096-byte logical blocks**, the Mac's GPT layout (EFI 499,998,720 B FAT32 + Linux exactly 120,000,000,000 B). The path ran: initramfs → `m5.root=s5` → switch_root → systemd 262 → SDDM autologin → uwsm **Hyprland (Omarchy session, bar up) on simpledrm + llvmpipe**. Screenshot `reports/27-vm-hyprland.png`. In the same run: first-boot online resize to the full 120 GB, and both loggers wrote to the ESP.

## Artifacts (hashes also in `~/m5boot/spec/inputs.md` § Rootfs boot v1)
| | sha256 |
|---|---|
| `build/rootfs-omarchy.ext4` 19,441,188,864 B (sparse; ext4, 4 KiB blocks, label `omarchy`, content 14.07 GB + 4 GiB + 1 GiB) | `927400aad577ef0e6b5c29efd196e8e0861495ffad35e6a72eac91f475614088` |
| `build/rootfs-omarchy.ext4.zst` 6,112,458,778 B | `c35fd888935309ffdabb6abbf95c0d129b50d3ce054ebe2cf08b1e02cd6cba76` |
| `build/desktop-v1/Image.gz` 4,040,470 B (slim + `tools/kernel/m5-desktop.config`) | `0a4835b871eed14205e4723294c41dee7de86d835c181776724c3f7f02e4db83` |
| `build/desktop-v1/t6050-j714s-C.dtb` (= slim v4 DTB C) | `8c1ce5c6ea17e45039b823cb2d72af811bb4369aec95841a43b75fe49cc54f24` |
| `build/initramfs-slim.cpio.gz` | `1e0882c6fa7f8485e42970b0fd5bc8549485aae2a9c10a96a42896cf9cca650a` |

Rebuild: `tools/rootfs/build-ext4.sh` (from `rootfs-omarchy.tar.zst` f9be6781…), `M5_O=… M5_KCONF_EXTRA=tools/kernel/m5-desktop.config tools/build-slim.sh`, `M5_SLIM=1 tools/initramfs/build.sh`.

## 1. Image
- Built from the existing signed-package tarball (unchanged, f9be6781…) + `tools/rootfs/m5-desktop-overlay.sh`. Rootless (userns); e2fsck clean; owners (alarm = 1000) and file capabilities (v2 `security.capability`, e.g. btop, gsr-kms-server) are preserved. **GNU tar drops those capabilities, so we use bsdtar.**
- Grows on first boot: `m5-resize-root.service`. resize2fs refused after switch_root ("Device or resource busy while opening /dev/nvme0n1p2": it didn't see / as mounted and tried an exclusive open). So the service makes the same online call itself, `EXT4_IOC_RESIZE_FS` on `/`. VM: `resized filesystem to 29296875` blocks (= 120,000,000,000 B).

## 2. Rootfs contents (overlay)
- **Autologin to Hyprland:** SDDM `[Autologin] User=alarm Session=hyprland-uwsm` (Omarchy's uwsm-managed session), VT1 (tty1). `default.target` = graphical. `alarm` gets Omarchy's `/etc/skel` (the deferred provisioning left it empty) and the video/input/seat groups. Accounts stay **locked** (`!`): no password login.
- **Software rendering:** `/etc/environment(.d)`: `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe AQ_DRM_DEVICES=/dev/dri/card0`. With simpledrm card0, Mesa uses llvmpipe. No GPU driver.
- **journald** `Storage=persistent`.
- **ESP log:** `m5-esplog.timer` (10 s after boot, then every 30 s) runs `m5-esplog-rootfs`. That copies `journalctl -b` + dmesg to `m5log/rootfs-<bootid>-{journal,dmesg}.txt`. It requires exactly one EFI-type partition of 200–1100 MB on nvme0n1, vfat, with the mount verified in /proc/mounts, and writes only `m5log/`. VM: both files written.
- fstab `LABEL=omarchy / ext4`. The USB gadget unit is removed (no ATC0 without PMP).
- **Expected harmless failures:** `ufw`/`m5-ufw-replay` (no netfilter in the kernel), the xdg-document-portal FUSE mount, wireplumber (no audio by design).

## 3. Initramfs `m5.root=s5`
- `/bin/m5-root` (busybox only) picks the **single** partition with GPT type Linux filesystem and size **exactly 120,000,000,000 B**. It checks the ext4 magic and the label `omarchy` read raw from the superblock, mounts it, and requires `/sbin/init`. Anything else gets REFUSE + reason (kmsg/earlycon) and the init stays in the initramfs shell.
- `/init`: logger first; with `m5.root=s5`, then m5-root. After 10 s it stops the initramfs logger, **unmounts the ESP** (found in the VM: a logger killed mid-write kept the ESP busy, and the rootfs logger got "Can't open blockdev"), moves /dev /proc /sys and runs `exec switch_root /newroot /sbin/init`.
- Logger: the m5boot session's v4 `m5-esplog` (its task 18; it reads the GPT itself, because our initramfs's sfdisk can't load its libraries, which is why my task 25 logger wrote nothing). Copied into `tools/initramfs/` with provenance and one change: **`m5.root=s5` turns the raw-s5 channel OFF**. Its own zero/M5LOG check would also refuse a disk0s5 that holds ext4.

## 4. Keyboard / trackpad: **none on the Mac with this build**
- The kernel has betizzel's patch 0005 (DockChannel MTP ring transport) plus `HID_DOCKCHANNEL`, `APPLE_DOCKCHANNEL`, RTKit and mailbox built in.
- At runtime it needs:
  - (a) the MTP coprocessor nodes **enabled**. Our DTs disable MTP + its DART since the task 24 SError, and the DAPF programming is unsolved (report 24).
  - (b) for the **trackpad only**, `apple/tpmtfw-j714s.bin` (`firmware-name` in the DT), extracted from the macOS restore bundle. It's **not in the rootfs**. The driver is built in and requests it when the interface starts, so it must be in the initramfs or under `/lib/firmware` before MTP probes. The keyboard needs no firmware.
- USB (keyboard or anything else) is off: ATC0 is PMP-gated (report 25).
- **So the desktop comes up but takes no input.** Next step for input: DAPF (report 24 §4), then re-enable MTP. Then add the trackpad firmware.

## 5. VM test details
- Kernel `build/vm-v1/Image` = the same slim + desktop config **plus `tools/kernel/m5-vm.config` (VM-only PCI NVMe/GIC/PL011; never for the Mac)**.
- DTB: QEMU's virt DTB + a RAM-backed `simple-framebuffer` 1280x800 x2r10g10b10 with a no-map reservation. That's the same simpledrm path as the Mac's static fb node. Same initramfs and image. 4 vCPUs (TCG, for speed; the Mac boots `maxcpus=1`, so expect a slower desktop).
- ESP content read back with the new `tools/fat32-cat.py` (stdlib, read-only): `boot-1.txt` (initramfs), `rootfs-<id>-journal.txt`, `rootfs-<id>-dmesg.txt`.

## macOS write procedure (PM; owner approval needed: writes disk0s5)
```sh
# 0. on ush: copy the image to the Mac (6.1 GB)
scp ~/m5-omarchy/build/rootfs-omarchy.ext4.zst macbook:/tmp/
# 1. on the Mac: read-only checks (stop if any line differs)
diskutil info disk0s5 | grep -E 'Device Node|Partition Type|Disk Size|Device Block Size|Mounted'
#    expect: /dev/disk0s5 | Linux Filesystem | 120.0 GB (120000000000 Bytes) | 4096 Bytes | Mounted: No
sudo dd if=/dev/rdisk0s5 bs=4096 count=1 2>/dev/null | head -c 5 | xxd      # zeros or "M5LOG"
# 2. decompress to a file first: /dev/rdisk needs whole 4096-byte blocks and BSD dd has no iflag=fullblock,
#    so a pipe straight into dd can fail on a short read. Needs ~19.5 GB free on Macintosh HD.
zstd -dc /tmp/rootfs-omarchy.ext4.zst > /tmp/rootfs-omarchy.ext4          # no zstd on the Mac? decompress on ush and scp the .ext4
shasum -a 256 /tmp/rootfs-omarchy.ext4                                       # 927400aad577ef0e6b5c29efd196e8e0861495ffad35e6a72eac91f475614088
# 3. write (19,441,188,864 B = 4,746,384 blocks of 4096)
sudo dd if=/tmp/rootfs-omarchy.ext4 of=/dev/rdisk0s5 bs=4m
# 4. verify: read back exactly the image length from the raw device
sudo dd if=/dev/rdisk0s5 bs=4096 count=4746384 2>/dev/null | shasum -a 256 # must equal 927400aa…4088
rm /tmp/rootfs-omarchy.ext4
```
Then boot m5boot with `build/desktop-v1/Image.gz` + DTB C + this initramfs, cmdline from inputs.md (`… m5.root=s5 m5.esplog=1`, plus `m5_pmgr_ro` if gz8 says so).
- **Read the result from macOS:** `sudo diskutil mount disk0s4; ls /Volumes/EFI/m5log/` (boot-N.txt = initramfs, rootfs-*-journal.txt = systemd/Hyprland).
- **Undo:** `sudo dd if=/dev/zero of=/dev/rdisk0s5 bs=4m count=1` (wipes the superblock; the initramfs then refuses s5 and stays in the shell).
