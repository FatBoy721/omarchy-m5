#!/bin/sh
# build-slim.sh: slim first-boot kernel (allnoconfig + tools/kernel/m5-slim.config) in build/linux-slim.
# Source: src/linux-asahi-wip72 as prepared by tools/build-kernel.sh (pins + betizzel patches),
# plus tools/kernel/patches/*.patch (ours; applied once, idempotent).
set -eu
R=$(cd "$(dirname "$0")/.." && pwd); K=$R/src/linux-asahi-wip72; O=$R/build/linux-slim
for p in "$R"/tools/kernel/patches/*.patch; do
  git -C "$K" apply --check "$p" 2>/dev/null && git -C "$K" apply "$p" && echo "applied $(basename "$p")" \
    || { git -C "$K" apply --check -R "$p" 2>/dev/null && echo "already applied $(basename "$p")" || { echo "patch fails: $p"; exit 1; }; }
done
D=$K/arch/arm64/boot/dts/apple
V=${M5_DT_VARIANT:-A}   # A: no USB; B: dwc3_0 without IOMMU; gz6: tools/kernel/dts/t6050-j714s-m5.dtsi (reset the SoC)
case $V in gz6) SRC=t6050-j714s-m5.dtsi ;; *) SRC=t6050-j714s-m5-$V.dtsi ;; esac
cp "$R/tools/kernel/dts/$SRC" "$D"/t6050-j714s-m5.dtsi; echo "DT variant $V ($SRC)"
grep -q 't6050-j714s-m5.dtsi' "$D"/t6050-j714s.dts || printf '\n#include "t6050-j714s-m5.dtsi"\n' >> "$D"/t6050-j714s.dts
# M5_KCONF_EXTRA: extra fragments appended to m5-slim.config (task 27: m5-desktop.config; VM: + m5-vm.config)
O=${M5_O:-$O}; CF=$O.allconfig; mkdir -p "$O"
cat "$R/tools/kernel/m5-slim.config" ${M5_KCONF_EXTRA:-} > "$CF"
make -C "$K" O="$O" ARCH=arm64 LLVM=1 KCONFIG_ALLCONFIG="$CF" allnoconfig >/dev/null
for s in M5FB_EARLYCON SERIAL_EARLYCON; do grep -q "^CONFIG_$s=y" "$O/.config" || { echo "CONFIG_$s not set"; exit 1; }; done
grep -q '^CONFIG_APPLE_WATCHDOG=y' "$O/.config" && { echo "APPLE_WATCHDOG still on"; exit 1; }
grep -q '^CONFIG_PANIC_TIMEOUT=0$' "$O/.config" || { echo "PANIC_TIMEOUT != 0"; exit 1; }
make -C "$K" O="$O" ARCH=arm64 LLVM=1 -j"$(nproc)" Image.gz apple/t6050-j714s.dtb
OUT=${M5_OUT:-$R/build/slim-v4}; mkdir -p "$OUT"; cp "$O/arch/arm64/boot/dts/apple/t6050-j714s.dtb" "$OUT/t6050-j714s-$V.dtb"
cp "$O"/arch/arm64/boot/Image "$O"/arch/arm64/boot/Image.gz "$OUT/"
sha256sum "$OUT"/Image "$OUT"/Image.gz "$OUT/t6050-j714s-$V.dtb"
