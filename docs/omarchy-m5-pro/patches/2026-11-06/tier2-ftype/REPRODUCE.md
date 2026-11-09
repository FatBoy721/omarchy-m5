# Reproducing the TIER2-FTYPE kernel (#28): keyboard-light power gate + dchid SET report type

**Status (2026-11-06):** built and reviewed, not yet booted. The native result, when there is one, goes into the running status at omacom/linux-aurora#293. Nothing here is proven on hardware yet.

## What changed on top of FT21
- **Platform runtime activation (published earlier under `platform-r2/`):** SMC children and NTAP are created only by explicit root writes after boot.
- **Keyboard backlight (`drivers/soc/apple/m5_kbdlight.c`, `drivers/pmdomain/apple/pmgr-pwrstate.c`; `src-tier2-kbd-vs-r3t.diff`):**
  - The board runs with power-manager writes skipped (`m5_pmgr_ro`). The FPWM0 domain is never allow-listed, so boot writes nothing to it.
  - `echo read > /sys/module/m5_kbdlight/parameters/activate`: repeatable and read-only. It reports the FPWM0 and parent (SIO) power-state words and a verdict.
  - `echo 1 > …`: creates the PWM and LED nodes only if FPWM0 is already powered. No power-manager write.
  - `echo force > …`: arms a one-shot kernel token that allows exactly one power-manager store, FPWM0 TARGET=ACTIVE with auto-gating left off. That happens only if FPWM0 reads plainly off (no auto-PM, busy or reset bits) and SIO reads on. Power-off, reset and probe writes stay skipped. On failure the PWM node is removed.
  - One actuation per boot. A refusal at the read-only checks does not spend it.
  - We have not authorized `force` for our own first native run.
- **dchid SET report type (`drivers/hid/dockchannel-hid/dockchannel-hid.c`; `src-dchid-set-report-type.diff`, written by our reviewer session):**
  - A HID-core feature SET is now framed as FEATURE (flags `0x80`) instead of always OUTPUT (`0x40`). Output SETs and all GETs are unchanged.
  - No new sender is added. On this firmware's live descriptors no automatic connect-time feature SET exists (no resolution-multiplier field).

## Inputs
- **Base:** `AsahiLinux/linux` commit `236788cd2602a24c703fe7bdaddaf73ef77d2027` (branch `asahi-wip-7.2`).
- **`tier2-ftype-full-vs-asahi-236788cd2.diff`** (sha256 `cfe86a50a216f8f5…`, full hash in `SHA256SUMS`): everything on top of the base. It is 56 files, text only (no binaries, firmware, device-tree dumps, calibration data or keys). It is a superset of the FT21 diff.
- **`tier2-ftype.config`.**
- **`tests/`:** host checks for the keyboard-light verdict and the power-on token (`sh tests/run.sh <linux tree>`).

## Build
```sh
git clone https://github.com/AsahiLinux/linux.git && cd linux
git checkout 236788cd2602a24c703fe7bdaddaf73ef77d2027
git apply ../tier2-ftype-full-vs-asahi-236788cd2.diff
mkdir ../obj && cp ../tier2-ftype.config ../obj/.config
make O=../obj ARCH=arm64 LLVM=1 olddefconfig
make O=../obj ARCH=arm64 LLVM=1 W=1 -j"$(nproc)" \
  KBUILD_BUILD_VERSION=28 KBUILD_BUILD_TIMESTAMP="Fri Nov  6 13:00:00 EST 2026" Image
```
- **Build inside a git checkout** (as for FT21): `scripts/setlocalversion` adds the `+` of `7.2.2-m5lk+`.
- **Our result:** `obj/arch/arm64/boot/Image` sha256 `5dba3502e85c9bb9b8d58df14040cef47e92ec4ba8d30f4aee7d91466d34fec7`, `uname -v` = `#28 SMP PREEMPT Fri Nov  6 13:00:00 EST 2026`. Toolchain: clang/LLD 23.1.3.
- **Reproducibility:** a fresh checkout of the base plus `git apply` of this full diff and this config, built as above, gave exactly `5dba3502…` (checked before publishing).
- **Keyboard-light-only build (#27, without the dchid change):** after applying the full diff, `git apply -p2 -R ../src-dchid-set-report-type.diff` (the per-change diffs carry two leading path components), then build with `KBUILD_BUILD_VERSION=27 KBUILD_BUILD_TIMESTAMP="Fri Nov  6 12:00:00 EST 2026"`. Our Image: `fe0ffbfca9314438146f442b7aa43978f42d7ec5a5ef100ed4a2b9dc92793b67`.

## Not included / not claimed
- Booting needs our m5boot loader chain and initramfs; this is not an installer.
- The battery driver is disabled (it hung the machine natively).
- Suspend, RTC writes and fan writes are not used.
- No trackpad mode command (`0xF3`) is sent by anything here.
- Physical trackpad pointer use is still UNCONFIRMED.
