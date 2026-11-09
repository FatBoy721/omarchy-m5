#!/bin/bash
# build-kernel.sh — reproducible J714s kernel + DTB build on a Linux host (user-level, clang/LLVM cross).
# Sources: AsahiLinux/linux asahi-wip-7.2 @ 236788cd + betizzel/omarchy-m5 @ 15cd70c1 (9 patches, DTs, configs).
# Needs: git clang lld llvm make dtc bison flex bc python3 (bc is required by Kbuild's timeconst).
# Output: build/linux/arch/arm64/boot/{Image,Image.gz,dts/apple/t6050-j714s.dtb}, modules, tools/t6050-probe/t6050_probe.ko,
# build/SHA256SUMS. Uses -j$(nproc).
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
LINUX_SHA=236788cd2602a24c703fe7bdaddaf73ef77d2027
M5_SHA=15cd70c1fad65322b85be4de4362cbed816a11c1
SRC=$R/src/linux-asahi-wip72 M5=$R/src/omarchy-m5 O=$R/build/linux
command -v bc >/dev/null || { echo "missing: bc (Kbuild needs it)"; exit 1; }

[ -d "$SRC/.git" ] || git clone --depth 1 -b asahi-wip-7.2 https://github.com/AsahiLinux/linux.git "$SRC"
[ -d "$M5/.git" ]  || git clone https://github.com/betizzel/omarchy-m5.git "$M5"
git -C "$SRC" checkout -q "$LINUX_SHA"; git -C "$M5" checkout -q "$M5_SHA"

for p in "$M5"/patches/linux/*.patch; do      # idempotent apply
  git -C "$SRC" apply --reverse --check "$p" 2>/dev/null || git -C "$SRC" apply "$p"
done
cp "$M5"/dt/*.dts "$M5"/dt/*.dtsi "$SRC/arch/arm64/boot/dts/apple/"
cp "$M5"/configs/*.config "$SRC/arch/arm64/configs/"
cp "$R"/tools/kernel/m5-safe.config "$SRC/arch/arm64/configs/"
# hardware-safety limits (task 10 addendum): no SMC node, no cpufreq node, no SMC-backed hwmon in the DT
D=$SRC/arch/arm64/boot/dts/apple
sed -i -e '/#include "t6050-cpufreq.dtsi"/d' -e '/#include "t6050-smc.dtsi"/d' "$D/t6050.dtsi"
sed -i -e '/#include "hwmon-common.dtsi"/d' -e '/#include "hwmon-fan-dual.dtsi"/d' -e '/#include "hwmon-laptop.dtsi"/d' "$D/t6050-j714s.dts"
grep -q t6050-j714s "$SRC/arch/arm64/boot/dts/apple/Makefile" ||
  echo 'dtb-$(CONFIG_ARCH_APPLE) += t6050-j714s.dtb t6050-j716s.dtb' >> "$SRC/arch/arm64/boot/dts/apple/Makefile"

K=(make -C "$SRC" ARCH=arm64 LLVM=1 O="$O" -j"$(nproc)")
mkdir -p "$O"
"${K[@]}" defconfig asahi.config omarchy-bringup.config omarchy-storage-net.config omarchy-smc.config m5-safe.config
"${K[@]}" Image.gz apple/t6050-j714s.dtb
"${K[@]}" modules                                   # all modules (rootfs), then our read-only probe module
"${K[@]}" M="$R/tools/t6050-probe" modules
cd "$O/arch/arm64/boot" && sha256sum Image.gz dts/apple/t6050-j714s.dtb | tee "$R/build/SHA256SUMS"
