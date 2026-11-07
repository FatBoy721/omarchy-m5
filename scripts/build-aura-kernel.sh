#!/usr/bin/env bash
# Reuse our patched kernel/DT without changing the working raw-m1n1 build.
# Disable fixed-address framebuffer markers before changing the boot-object layout.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f vendor/linux/.config ]; then
    echo "ERROR: configure/build the existing J714s kernel with make kernel first." >&2
    exit 1
fi
mkdir -p build/aura-test/boot
work="$(mktemp -d "$PWD/build/aura-kernel.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
# A separate in-tree build also works when vendor/linux is already built.
# Linux rejects O= builds against a source tree with generated config/headers.
if [ "$(uname -s)" = Linux ]; then
    cp -a --reflink=auto vendor/linux "$work/linux"
else
    cp -a vendor/linux "$work/linux"
fi
"$work/linux/scripts/config" --file "$work/linux/.config" \
    --disable OMARCHY_FB_MARKERS --set-str LOCALVERSION -aura-j714s-test
LINUX="$work/linux" scripts/build-kernel.sh olddefconfig
LINUX="$work/linux" KEEP_CONFIG=1 scripts/build-kernel.sh

install -m 0644 "$work/linux/arch/arm64/boot/Image.gz" build/aura-test/boot/Image.gz
install -m 0644 "$work/linux/arch/arm64/boot/dts/apple/t6050-j714s.dtb" \
    build/aura-test/boot/t6050-j714s.dtb
install -m 0644 "$work/linux/.config" build/aura-test/kernel.config
printf '\nDiagnostic kernel saved; vendor/linux and its boot artifacts were not rebuilt.\n'
