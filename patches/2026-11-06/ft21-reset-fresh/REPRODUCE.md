# Reproducing the FT21 kernel (trackpad READY build)

FT21 produced the first **firmware-READY** internal trackpad on the J714s (14" MacBook Pro, M5 Pro, Mac17,9, T6050).
- The pulse runs after the firmware's own reset request (`0xa2`): a host AFE reset pulse on SMC `pcIO` with the two existing values, release always sent, then a fresh firmware image and power-ON only.
- The native result is in the running status at omacom/linux-aurora#293. **Physical pointer use was still being confirmed** when this was published.

## Inputs
- **Base:** `AsahiLinux/linux` commit `236788cd2602a24c703fe7bdaddaf73ef77d2027` (branch `asahi-wip-7.2`).
- **`ft21-full-vs-asahi-236788cd2.diff`** (sha256 `93ee6bbd4d414eecbc907b96e02b50236865387256296376dbc1c96bb2afa8b0`): everything on top of that base. That is our earlier bring-up work (FT1–FT19) plus the FT21 change: 52 files, no binaries. Per-file licenses and upstream attributions are kept in the code.
- **`src-dchid-ft21.diff`:** the FT21 change alone, against our FT19 tree (`drivers/hid/dockchannel-hid/dockchannel-hid.c`).
- **`ft21.config`** (sha256 `81d25365b4ce60961d84225fd17f00c03f62ecf6c0da3aa4d8965ad7ce806077`).

## Build
```sh
git clone https://github.com/AsahiLinux/linux.git && cd linux
git checkout 236788cd2602a24c703fe7bdaddaf73ef77d2027
git apply ../ft21-full-vs-asahi-236788cd2.diff
mkdir ../obj && cp ../ft21.config ../obj/.config
make O=../obj ARCH=arm64 LLVM=1 olddefconfig
make O=../obj ARCH=arm64 LLVM=1 W=1 -j"$(nproc)" \
  KBUILD_BUILD_VERSION=23 KBUILD_BUILD_TIMESTAMP="Fri Nov  6 07:00:00 EST 2026" Image
```
- **Our result:** `obj/arch/arm64/boot/Image` sha256 `faeec23e6f646e2a676cc136f7a72e22d136ac3b0e173787497f8275680192c2`, `uname -v` = `#23 SMP PREEMPT Fri Nov  6 07:00:00 EST 2026`.
- **Reproducibility:** an independent from-scratch rebuild on our side (FT19 tree + `src-dchid-ft21.diff`) gave the same hash. Toolchain: clang/LLD 23.1.3. Other toolchains build fine but won't match the hash.

## Using it (what we did; adapt with care)
- **Not included:** booting needs our m5boot loader chain and initramfs, which is not a turnkey installer. No Apple firmware, device tree dumps, calibration data or keys are included or needed from us.
- **Trackpad sequence on a booted system:**
  1. Boot with `macsmc.m5_pcio_budget=2` (exactly once) and firmware-managed power method 2 (`m5_dchid_pm2=fw`).
  2. Wait for the initial start to fail. You will see an `m5: fw reset request 0xa2 iface 1` line and `iface multi-touch start timed out`.
  3. As root: `echo 1 > /sys/module/dockchannel_hid/parameters/m5_mt_reset_fresh`, then open the multi-touch event device once.
  4. The kernel refuses unless every gate holds, sends at most the two writes, and logs each step.
- **Desktop:** after READY, `udevadm trigger --action=add --sysname-match=event<N>` let the desktop pick the device up, because its boot-time open had failed during the initial timeout.
- **No automatic policy exists.** This is a one-shot, default-off test mechanism.
