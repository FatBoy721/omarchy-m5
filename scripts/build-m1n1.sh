#!/usr/bin/env bash
# omarchy-m5 dev harness - build m1n1 for T6050.
#
# Produces (M1N1 defaults to vendor/m1n1):
#   $M1N1/build/m1n1.bin   - raw stage-1 image for kmutil configure-boot
#   $M1N1/build/m1n1.macho - Mach-O variant
#
# CHAINLOADING=1 (default) builds a chainloadable image: the installed
# stage-1 m1n1 loads this build over USB via proxyclient, giving a ~7s
# dev iteration cycle without touching boot policy. Set CHAINLOADING=0
# for the image you actually install via kmutil.
# M1N1=build/m1n1-gpu selects an independently prepared GPU trial tree.
set -euo pipefail

cd "$(dirname "$0")/.."

M1N1="${M1N1:-vendor/m1n1}"
if [ ! -d "$M1N1" ]; then
    echo "ERROR: $M1N1 missing; prepare the selected source tree first." >&2
    exit 1
fi

# Put the active rustup toolchain's bin dir first so its cargo (which has
# the aarch64-unknown-none-softfloat target) wins over a distro rustc.
# rustup may be a per-user install that is not on PATH (~/.cargo/bin).
RUSTUP="$(command -v rustup || echo "$HOME/.cargo/bin/rustup")"
RUSTUP_BIN="$(dirname "$("$RUSTUP" which cargo)")"
export PATH="$RUSTUP_BIN:$PATH"
# On macOS, brew LLVM provides clang/lld (m1n1's Makefile finds it via
# llvm-config); Linux hosts use the distro clang/lld.
if [ "$(uname -s)" = Darwin ]; then
    export PATH="$(brew --prefix llvm)/bin:$PATH"
fi

CHAINLOADING="${CHAINLOADING:-1}"
RELEASE="${RELEASE:-0}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

# m1n1's build/build_cfg.h rule has no prerequisites, so once the file exists
# make treats it as up to date and never re-evaluates CFG. Flipping
# CHAINLOADING/RELEASE would then silently produce the *previous* config.
# Compare the config ourselves and delete the header when it has to change.
CFG_FILE="$M1N1/build/build_cfg.h"
WANT=""
[ "$RELEASE" = 1 ] && WANT="$WANT#define RELEASE"$'\n'
[ "$CHAINLOADING" = 1 ] && WANT="$WANT#define CHAINLOADING"$'\n'
if [ -f "$CFG_FILE" ] && [ "$(cat "$CFG_FILE")" != "${WANT%$'\n'}" ]; then
    echo "==> build config changed -> forcing rebuild"
    rm -f "$CFG_FILE"
fi

# m1n1's Makefile uses grouped targets ("&:"), which need GNU Make >= 4.3.
# macOS ships 3.81, which silently mis-parses them into a target named "&"
# and then fails to regenerate build_cfg.h.
GMAKE="$(command -v gmake || command -v make)"
case "$("$GMAKE" --version | head -1)" in
    *" 3."*) echo "ERROR: $GMAKE is too old for m1n1; brew install make" >&2; exit 1 ;;
esac

echo "==> Building $M1N1 (CHAINLOADING=$CHAINLOADING, RELEASE=$RELEASE, -j$JOBS)"
"$GMAKE" -C "$M1N1" -j"$JOBS" CHAINLOADING="$CHAINLOADING" RELEASE="$RELEASE"

echo
echo "==> Artifacts:"
ls -lh "$M1N1/build/m1n1.bin" "$M1N1/build/m1n1.macho" 2>/dev/null || true
