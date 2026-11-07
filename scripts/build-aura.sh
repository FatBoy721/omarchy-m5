#!/usr/bin/env bash
# Build an unconfigured, proxy-only Aura Stage 1; never enroll it on a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

AURA_REPO=https://github.com/aurora-silicon/aura.git
AURA_TAG=v1.0.0b4
AURA_REV=8b15096337e97f934438e1e7f3e96182440351dc
if [ ! -e vendor/aura ]; then
    mkdir -p vendor
    git clone --depth 1 --branch "$AURA_TAG" --recurse-submodules "$AURA_REPO" vendor/aura
fi
if [ "$(git -C vendor/aura rev-parse HEAD)" != "$AURA_REV" ]; then
    echo "ERROR: vendor/aura must be $AURA_TAG ($AURA_REV); leaving this checkout untouched." >&2
    exit 1
fi
if ! git -C vendor/aura diff --quiet || ! git -C vendor/aura diff --cached --quiet; then
    echo "ERROR: vendor/aura has tracked changes; this candidate requires the unmodified pin." >&2
    exit 1
fi

# Match the existing m1n1 build's rustup selection, not a distro cargo.
RUSTUP="$(command -v rustup || echo "$HOME/.cargo/bin/rustup")"
RUSTUP_BIN="$(dirname "$("$RUSTUP" which cargo)")"
export PATH="$RUSTUP_BIN:$PATH"
if [ "$(uname -s)" = Darwin ]; then
    export PATH="$(brew --prefix llvm)/bin:$PATH"
fi
GMAKE="$(command -v gmake || command -v make)"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

# CHAINLOADING enables Stage 1 support, not automatic disk boot. The factory
# config has no ESP UUID/target and remains a proxy indefinitely. Do not fill it.
# Keep NV2 off: this experiment is the upstream native EL1/EL2 handoff.
"$GMAKE" -C vendor/aura -j"$JOBS" all USE_CLANG=1 RELEASE=0 CHAINLOADING=1 \
    ESP_STAGE2=0 DEBUGUSB_PROXY=0 NV2_BOOT=0 NV2_TRACE=0 NV2_TRACE_PRINT=0 \
    BUILTIN_LOGO=aurora LOGO=

mkdir -p build/aura-test/boot
install -m 0644 vendor/aura/build/aura.bin build/aura-test/boot/aura-stage1.bin
install -m 0644 vendor/aura/build/aura-boot.macho build/aura-test/boot/aura-boot.macho
install -m 0644 vendor/aura/build/build_cfg.h build/aura-test/aura-build-config.h
printf '%s\n' "$AURA_REV" > build/aura-test/aura-revision
printf '\nBuilt %s. Nothing installed; make aura-test prepares the diagnostic bundle.\n' "$AURA_TAG"
