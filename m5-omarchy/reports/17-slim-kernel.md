# 17 — Slim first-boot kernel + initramfs (boot object well under 11 MiB)

Context: the 192 KB probe also panicked (NATIVE), so **size is not the cause** of the fuOS panic. The slim set is kept as a smaller and faster option, not as a fix.

| Artifact | Size | Notes |
|---|---|---|
| Image (slim) | 7,907,336 B | allnoconfig + `tools/kernel/m5-slim.config`, everything built in |
| Image.gz (gzip -9) | **3,105,641 B** | what m5boot inflates today |
| Image.xz (`xz -9e`) | 2,296,052 B | -26 %; would need an xz decoder in m5boot |
| Image.zst (`zstd -19`) | 2,616,368 B | -16 %; would need a zstd decoder |
| initramfs-slim.cpio.gz | **2,143,952 B** | base set minus e2fsck/fsck.*/econftool, with the slim probe .ko (was 2,369,383 B) |
| DTB | 65,890 B | unchanged |
| **Projected m5boot-gz** | **≈ 5.3 MB + shim** | was 18.9 MB |

- Symbols: all the requested ones are set, except VHE/PAN/LSE (no longer Kconfig options in this tree), KEXEC (KEXEC_FILE=y suffices) and HID_APPLE (dependency). Safety limits are re-asserted (no SOUND/MACSMC/CPU_FREQ/DRM_APPLE/DRM_ASAHI/fb markers).
- Build: `M5_SLIM=1 sh tools/initramfs/build.sh` builds only the slim initramfs. The base/loader hashes were verified unchanged (37237b5c…, 4a8f0183…).
- Caveat: `tools/t6050-probe/t6050_probe.ko` is now built for the slim kernel. Rebuild it with build-kernel.sh before rebuilding the main initramfs.
- **Untested** (VM and NATIVE). Hashes are in `~/m5boot/spec/inputs.md` § Slim.
- Recommendation: the xz/zstd gains (0.5–0.8 MB) aren't worth a new decoder; stay with gzip.
