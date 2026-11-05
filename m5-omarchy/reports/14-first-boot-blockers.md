# 14 — First-boot blockers (found by the m5boot implementer in VM), fixed

## 1. `/init` exited, causing a kernel panic
- **Cause:** `exec setsid cttyhack sh`. Alpine `busybox-static-1.37.0-r31` (verified package, task 07) has **no `cttyhack` applet** (`busybox --list`, 305 applets; `sulogin` is absent too). The exec failed, PID 1 exited, and the kernel reported "Attempted to kill init".
- **Fix** (`tools/initramfs/init`, sha256 `4e8f8961…475c`):
  - PID 1 never exits. After starting `m5-gadget-net` and `m5-sshd` in the background (and `m5-loader` if `m5.loader=1`), it loops forever: `setsid sh -c "exec sh </dev/$con >/dev/$con 2>&1"`.
  - `$con` is the last entry of `/sys/class/tty/console/active`, the device behind `/dev/console` (`tty0` on the Mac with `console=tty0`). Opening it in a new session makes it the shell's controlling terminal, which is what `cttyhack` does.
  - If the shell exits it is respawned after 1 s.
- **Applets checked:** every command used by `init`, `m5-gadget-net`, `m5-sshd`, `m5-loader` and `install-rootfs.sh` exists as a busybox applet or a shipped binary. `kexec` exists only in the loader variant, the only place it's used.
- The same `init` goes into both initramfs variants.
- **VM test** (QEMU `virt`, cortex-a72; **test-only kernel** = stock ALARM `linux-aarch64` `/boot/Image` from the GPG-verified ALARM tarball, because our 16K Apple-config kernel produces no output under TCG; log `build/qemu-test/vm-test.log`):
  - The banner printed (`nproc: 1`, compatible, model).
  - `exit` → "console shell on /dev/ttyAMA0 exited; respawning in 1 s" → the new shell ran `echo T2-respawned`.
  - `pidof dropbear` → 74; `netstat -ltn` → `0.0.0.0:22` and `:::22` LISTEN.
  - No "Attempted to kill init".
  - `m5-gadget-net: no configfs usb_gadget` is expected with the ALARM test kernel and no UDC. The gadget is NATIVE-only.

## 2. Hard-coded framebuffer writes
- **Source:** betizzel's `patches/linux/0001-t6050-early-fb-markers.patch` (omarchy-m5 @15cd70c1).
  - It adds `CONFIG_OMARCHY_FB_MARKERS` with `OMARCHY_FB_MARKER_BASE` default `0x10bd3110000` ("as reported by the bootloader (m1n1 prints it…)"), stride `0x2f40` (3024×4) and height 1964.
  - At kernel entry (`head.S`: `mov_q x9, 0x3FF00000 // red, x2r10g10b10`), after the MMU comes up, at `paging_init` and at console init, it paints bands at that fixed PA.
  - It also sets up `earlycon=efifb` on it.
  - It was enabled by betizzel's `configs/omarchy-bringup.config:51-54`.
- **Fix:** `# CONFIG_OMARCHY_FB_MARKERS is not set`, appended to `tools/kernel/m5-safe.config` (merged last; sha256 `d24c012c…55a3`).
  - The patch's header turns every hook into an empty inline stub when the option is off (`static inline void omarchy_fb_marker(int slot) { }`, `omarchy_fb_earlycon_init(void) { }`). Every other hunk is `#ifdef CONFIG_OMARCHY_FB_MARKERS`.
  - **Checked:** `.config` line 11155 is now unset; 0 `omarchy_fb*` symbols in `System.map`; the new `Image` contains 0 occurrences of `0x10bd3110000` (u64 LE) or of its low 32 bits.
- **`earlycon=efifb` dropped** from the suggested bootargs (inputs.md) and the rootfs `/boot/cmdline`, because its only screen_info came from that fixed-address code.

## New artifacts (all in `~/m5boot/spec/inputs.md`; old hashes listed there as superseded)
| Artifact | SHA-256 |
|---|---|
| `Image` | `9c377f51e6e9b1266f117f969d7ef2ed14bf1b8f40542e72e9e17c4f01e4b5e6` (image_size 0x2d50000, flags 0xc unchanged) |
| `Image.gz` | `63835275b84f4bd7e0e156ab399cde792bb3f30f7d0db4a32cafe1b7c80a1a37` |
| `t6050-j714s.dtb` | `23dabefb…1d6d` (unchanged) |
| `initramfs.cpio.gz` | `37237b5c8693a433b6655136ac52230dc15822786d189fb7895676f6934de48b` |
| `initramfs-loader.cpio.gz` | `4a8f0183bc7de8cb9561ea1cf46d18c9741c55a316b87f49fab462a24e55d2ca` |
| `rootfs-alarm.tar.zst` | `32f5b7ee35d1e5dcf9a6144e85ef1576c0d730609c6eb5b232c464155ac6e6f3` |

Task 13 resumes from `build/omarchy-build/RESUME-13.md`. Its base must be re-extracted from this new `rootfs-alarm.tar.zst`, which carries the fixed kernel.
