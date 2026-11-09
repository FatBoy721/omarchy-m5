#!/usr/bin/env bash
# omarchy-m5: isolated J714s Mesa PR194 trial; never installs onto the Mac/host.
#
# Usage:
#   scripts/build-mesa-gpu.sh prepare    # fetch immutable sources, copy sysroot
#   scripts/build-mesa-gpu.sh bootstrap  # install pinned Python tools locally
#   scripts/build-mesa-gpu.sh bootstrap-host # signed LLVM translator, local prefix
#   scripts/build-mesa-gpu.sh build      # native tools + cross Mesa/runtime + probes
#   scripts/build-mesa-gpu.sh runtime    # add Vulkan loader + repackage staged Mesa
#   scripts/build-mesa-gpu.sh package    # finish probes/archive; requires runtime
#   scripts/build-mesa-gpu.sh help
#
# Host prerequisites: git, uv, ninja, cmake (>=3.22.1), pkgconf, bison, flex, wayland-scanner,
# aarch64-linux-gnu-gcc/g++, LLVM/Clang development files, SPIRV-Tools and
# spirv-llvm-translator matching LLVM's major.minor. bootstrap-host extracts a
# signed Arch package locally (23.1.2 matches this host's LLVM 23.1.3).
# Asahi + zink + Borealis at this pin do NOT enable Mesa's Rust components;
# neither bindgen nor a target Rust standard library nor QEMU is required.
#
# Cross compilation follows Mesa's supported two-build precompiler path.
# Host LLVM is used only by the native tools, never linked into target Mesa.
# Target libraries and GCC C++ headers come ONLY from the saved Mac sysroot.
# Existing sysroot, distro Mesa, Hyprland, configuration and bundles are untouched.
# The private target has no software driver: leaving its launcher returns to
# the existing distro llvmpipe session rather than disguising a failed GPU trial.
#
# The archive contains an /opt prefix, not /usr replacements. After separately
# authorized deployment at that exact prefix, use bin/mesa-j714s-gpu native|zink
# COMMAND [ARGS...]. The launcher changes only the command's environment.
# Discover the aurora/asahi render node on the Mac; do not assume renderD128:
#   readlink -f /sys/class/drm/renderD*/device/driver
#   /opt/mesa-j714s-gpu-043a4c58080c/bin/mesa-j714s-gpu native \
#     /opt/mesa-j714s-gpu-043a4c58080c/bin/gl-native-smoke /dev/dri/renderDNNN
# Repeat with zink: this exercises Borealis Vulkan through zink, including
# pixel readback, compute SSBO results and shared-memory compute. It is not
# a standalone Vulkan conformance test. No shim is installed or preloaded.
# Launch a new compositor only after stopping the old one via normal session
# management: .../mesa-j714s-gpu native /usr/local/bin/Hyprland
# Exit that process; outside the launcher restore explicit software rendering:
#   env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe start-hyprland
# This uses the untouched distro libraries and existing session/configuration.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/build/mesa-gpu"
SRC="$WORK/source"
PROBES="$WORK/probes-source"
SYSROOT="$WORK/sysroot"
REFERENCE="$ROOT/build/hyprland-dcp-sysroot"
MESA_SHA=043a4c58080c4951fea3797fe45fc6898ce77632
PROBE_SHA=c9dbba61122f2472f9c38d9d9f31144e5e77a2be
# Match Mesa's bundled VK_HEADER_VERSION=363 and the loader's known_good.json.
# Official v1.4.363 tags, resolved to commits (Headers uses an annotated tag).
VULKAN_VERSION=1.4.363
VULKAN_LOADER_SHA=9e9518d2cf00054a220ae1a40f4406804b420ef5
VULKAN_HEADERS_SHA=6802bb4733b63ed5efd3adb308a6c885ef180ea1
VULKAN_WORK="$WORK/vulkan-runtime"
PREFIX=/opt/mesa-j714s-gpu-043a4c58080c
STAGE="$WORK/stage"
TOOLS="$WORK/tools"
HOST_DEPS="$WORK/host-deps"
JOBS=${JOBS:-$(nproc)}

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "Required host program: $1"; }

# Never reset an existing tree or silently accept an extra downstream patch.
source_at_pin() {
    local path=$1 url=$2 sha=$3 sparse=${4:-}
    if [[ ! -d "$path/.git" ]]; then
        [[ ! -e "$path" ]] || fail "$path already exists without .git; preserve it manually"
        git init -q "$path"
        git -C "$path" remote add origin "$url"
        [[ -z "$sparse" ]] || git -C "$path" sparse-checkout set "$sparse" LICENSES
        git -C "$path" fetch --depth=1 origin "$sha"
        git -C "$path" checkout -q --detach FETCH_HEAD
    fi
    [[ $(git -C "$path" rev-parse HEAD) == "$sha" ]] || fail "Unexpected source pin: $path"
    [[ -z $(git -C "$path" status --porcelain --untracked-files=all) ]] || fail "Modified source: $path (left untouched)"
}

prepare() {
    need git
    need python3
    need readelf
    mkdir -p "$WORK"
    source_at_pin "$SRC" https://github.com/aurora-silicon/mesa.git "$MESA_SHA"
    source_at_pin "$PROBES" https://github.com/rolotrealanis98/m5pro-linux.git "$PROBE_SHA" \
        contrib/pending/gpu/gl-native/tests
    [[ -d "$REFERENCE/usr/include/c++/16.1.1/aarch64-unknown-linux-gnu" ]] || \
        fail "Missing saved target GCC 16.1.1 headers in $REFERENCE"
    if [[ ! -e "$SYSROOT" ]]; then
        [[ ! -e "$SYSROOT.partial" ]] || fail "Interrupted sysroot copy: preserve/remove $SYSROOT.partial manually"
        cp -a --reflink=auto "$REFERENCE" "$SYSROOT.partial"
        # Absolute links copied from a target must never escape into host /usr.
        python3 - "$SYSROOT.partial" <<'PY'
import os, sys
root = os.path.abspath(sys.argv[1])
for directory, dirs, files in os.walk(root, followlinks=False):
    for name in dirs + files:
        path = os.path.join(directory, name)
        if os.path.islink(path):
            target = os.readlink(path)
            if os.path.isabs(target):
                os.unlink(path)
                os.symlink(os.path.relpath(root + target, directory), path)
PY
        mv "$SYSROOT.partial" "$SYSROOT"
        # Record exact input bytes and symlink targets, independent of mtimes.
        python3 - "$SYSROOT" "$WORK/sysroot-inputs.sha256" <<'PY'
import hashlib, os, sys
root, manifest = sys.argv[1:]
with open(manifest, 'w') as out:
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        for name in sorted(dirs + files):
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, root)
            if os.path.islink(path):
                out.write('link ' + rel + ' -> ' + os.readlink(path) + '\n')
            elif os.path.isfile(path):
                with open(path, 'rb') as inp:
                    digest = hashlib.file_digest(inp, 'sha256').hexdigest()
                out.write(digest + '  ' + rel + '\n')
PY
    fi
    [[ -f "$WORK/sysroot-inputs.sha256" ]] || fail "Sysroot lacks its input manifest; do not reuse an incomplete copy"
    for lib in libc.so.6 libstdc++.so.6 libEGL.so libGLESv2.so; do
        [[ -f "$SYSROOT/usr/lib/$lib" ]] || fail "Missing target library: $lib"
        [[ $(LC_ALL=C readelf -h "$SYSROOT/usr/lib/$lib") == *AArch64* ]] || fail "Non-aarch64 target library: $lib"
    done
}

bootstrap() {
    need uv
    mkdir -p "$WORK"
    [[ -d "$TOOLS" ]] || uv venv "$TOOLS"
    uv pip install --python "$TOOLS/bin/python" \
        meson==1.9.1 Mako==1.3.10 MarkupSafe==3.0.2 packaging==25.0 \
        PyYAML==6.0.3 ply==3.11
}

# No pacman transaction, install scripts, trust imports, root or host writes.
# An unavailable/untrusted signature is a hard failure, never bypassed.
bootstrap_host() {
    for tool in curl pacman-key bsdtar python3 sha256sum; do need "$tool"; done
    local archive=spirv-llvm-translator-23.1.2-1-x86_64.pkg.tar.zst
    local url=https://stable-mirror.omarchy.org/extra/os/x86_64
    mkdir -p "$WORK/downloads"
    for file in "$archive" "$archive.sig"; do
        if [[ ! -f "$WORK/downloads/$file" ]]; then
            curl --fail --location "$url/$file" -o "$WORK/downloads/$file.partial"
            mv "$WORK/downloads/$file.partial" "$WORK/downloads/$file"
        fi
    done
    pacman-key --verify "$WORK/downloads/$archive.sig" "$WORK/downloads/$archive"
    if [[ -f "$WORK/downloads/translator.sha256" ]]; then
        (cd "$WORK/downloads" && sha256sum -c translator.sha256)
    else
        (cd "$WORK/downloads" && sha256sum "$archive" > translator.sha256)
    fi
    [[ ! -e "$HOST_DEPS" ]] || fail "$HOST_DEPS already exists; preserve it (bootstrap-host is one-time)"
    mkdir -p "$HOST_DEPS"
    bsdtar -xf "$WORK/downloads/$archive" -C "$HOST_DEPS"
    python3 - "$HOST_DEPS" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
pc = root / 'usr/lib/pkgconfig/LLVMSPIRVLib.pc'
text = pc.read_text()
if '/usr' not in text:
    raise SystemExit('Unexpected translator pkg-config layout')
pc.write_text(text.replace('/usr', str(root / 'usr')))
PY
}

# Meson receives explicit native and cross files; inherited build flags or
# pkg-config overrides cannot accidentally mix this snapshot with host libs.
clean_build_env() {
    unset CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS PKG_CONFIG_PATH \
        PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR CMAKE_PREFIX_PATH \
        LD_LIBRARY_PATH LD_PRELOAD DESTDIR MESON_CROSS_FILE MESON_NATIVE_FILE
    export PATH="$WORK/host-prefix/bin:$TOOLS/bin:$PATH"
    # Only build-host processes execute here; no target ELF is ever executed.
    export LD_LIBRARY_PATH="$HOST_DEPS/usr/lib"
}

# Zink dlopens this library: Mesa's DT_NEEDED closure alone cannot validate it.
# This step never calls prepare/bootstrap or rebuilds Mesa/native shader tools.
# Headers and CMake install metadata stay in the private build tree; only the
# runtime library, relative links, licenses and provenance enter the /opt stage.
build_vulkan_runtime() (
    for tool in git cmake ninja pkg-config python3 readelf sha256sum tar \
        aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ aarch64-linux-gnu-ar; do need "$tool"; done
    [[ -f "$WORK/sysroot-inputs.sha256" && -d "$SYSROOT/usr/include/c++/16.1.1" ]] || \
        fail "Run prepare first; the private target SDK is required"
    clean_build_env
    unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH ASMFLAGS CMAKE_TOOLCHAIN_FILE
    export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
    pkg-config --exists xcb x11 xrandr wayland-client || \
        fail "Target SDK lacks XCB/Xlib/Xrandr/Wayland; do not disable WSI to work around it"
    local loader="$VULKAN_WORK/loader-source" headers="$VULKAN_WORK/headers-source"
    local headers_prefix="$VULKAN_WORK/headers-prefix" dest="$STAGE$PREFIX"
    local provenance="$dest/share/j714s-gpu/vulkan-runtime"
    mkdir -p "$VULKAN_WORK"
    source_at_pin "$loader" https://github.com/KhronosGroup/Vulkan-Loader.git "$VULKAN_LOADER_SHA"
    source_at_pin "$headers" https://github.com/KhronosGroup/Vulkan-Headers.git "$VULKAN_HEADERS_SHA"
    cat > "$VULKAN_WORK/cross.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_ASM_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_AR aarch64-linux-gnu-ar)
set(CMAKE_SYSROOT "$SYSROOT")
set(CMAKE_FIND_ROOT_PATH "$SYSROOT" "$headers_prefix")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_USE_PACKAGE_REGISTRY OFF)
set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY OFF)
set(CMAKE_CXX_FLAGS_INIT "-nostdinc++ -isystem $SYSROOT/usr/include/c++/16.1.1 -isystem $SYSROOT/usr/include/c++/16.1.1/aarch64-unknown-linux-gnu -isystem $SYSROOT/usr/include/c++/16.1.1/backward")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L$SYSROOT/usr/lib -Wl,-rpath-link,$SYSROOT/usr/lib")
EOF
    cmake -S "$headers" -B "$VULKAN_WORK/headers-build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$VULKAN_WORK/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$headers_prefix" -DCMAKE_BUILD_TYPE=Release \
        -DVULKAN_HEADERS_ENABLE_TESTS=OFF -DVULKAN_HEADERS_ENABLE_MODULE=OFF \
        -DVULKAN_HEADERS_ENABLE_INSTALL=ON
    cmake --install "$VULKAN_WORK/headers-build"
    cmake -S "$loader" -B "$VULKAN_WORK/loader-build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$VULKAN_WORK/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
        -DVULKAN_HEADERS_INSTALL_DIR="$headers_prefix" \
        -DVulkanHeaders_DIR="$headers_prefix/share/cmake/VulkanHeaders" \
        -DPython3_EXECUTABLE="$(command -v python3)" \
        -DPKG_CONFIG_EXECUTABLE="$(command -v pkg-config)" \
        -DUPDATE_DEPS=OFF -DBUILD_TESTS=OFF -DLOADER_CODEGEN=OFF -DUSE_GAS=ON \
        -DBUILD_WSI_XCB_SUPPORT=ON -DBUILD_WSI_XLIB_SUPPORT=ON \
        -DBUILD_WSI_XLIB_XRANDR_SUPPORT=ON -DBUILD_WSI_WAYLAND_SUPPORT=ON \
        -DBUILD_WSI_DIRECTFB_SUPPORT=OFF
    cmake --build "$VULKAN_WORK/loader-build" --parallel "$JOBS"
    DESTDIR="$VULKAN_WORK/install" cmake --install "$VULKAN_WORK/loader-build"
    mkdir -p "$dest/lib" "$provenance/loader" "$provenance/headers"
    cp -a "$VULKAN_WORK/install$PREFIX/lib/libvulkan.so" \
        "$VULKAN_WORK/install$PREFIX/lib/libvulkan.so.1" \
        "$VULKAN_WORK/install$PREFIX/lib/libvulkan.so.$VULKAN_VERSION" "$dest/lib/"
    cp "$loader/LICENSE.txt" "$loader/REUSE.toml" "$provenance/loader/"
    cp -a "$loader/LICENSES" "$provenance/loader/"
    # Preserve the embedded cJSON MIT copyright/permission notice as well.
    cp "$loader/loader/cJSON.h" "$provenance/loader/"
    cp "$headers/LICENSE.md" "$headers/REUSE.toml" "$provenance/headers/"
    cp -a "$headers/LICENSES" "$provenance/headers/"
    cp "$loader/scripts/known_good.json" "$provenance/"
    cp "$VULKAN_WORK/cross.cmake" "$provenance/"
    cat > "$provenance/source-pins.txt" <<EOF
Vulkan-Loader https://github.com/KhronosGroup/Vulkan-Loader.git $VULKAN_LOADER_SHA (v$VULKAN_VERSION)
Vulkan-Headers https://github.com/KhronosGroup/Vulkan-Headers.git $VULKAN_HEADERS_SHA (v$VULKAN_VERSION)
WSI: XCB, Xlib, Xlib-Xrandr, Wayland; GAS AArch64 trampolines enabled
Prefix: $PREFIX
Recipe: scripts/build-mesa-gpu.sh runtime
EOF
    sha256sum "$WORK/sysroot-inputs.sha256" > "$provenance/sysroot-manifest.sha256"
    require_vulkan_runtime
    LC_ALL=C readelf -h -d -V "$dest/lib/libvulkan.so.$VULKAN_VERSION" \
        > "$WORK/vulkan-runtime-elf-report.txt"
    cp "$WORK/vulkan-runtime-elf-report.txt" "$provenance/elf-report.txt"
    (cd "$dest" && sha256sum "lib/libvulkan.so.$VULKAN_VERSION") > "$provenance/runtime.sha256"
    # A deployment delta, deliberately excluding existing Mesa/launcher files.
    tar -C "$STAGE" -czf "$WORK/mesa-j714s-gpu-043a4c58080c-vulkan-runtime.tar.gz" \
        "${PREFIX#/}/lib/libvulkan.so" "${PREFIX#/}/lib/libvulkan.so.1" \
        "${PREFIX#/}/lib/libvulkan.so.$VULKAN_VERSION" \
        "${PREFIX#/}/share/j714s-gpu/vulkan-runtime"
    echo "Runtime delta: $WORK/mesa-j714s-gpu-043a4c58080c-vulkan-runtime.tar.gz"
    echo "Runtime ELF report: $WORK/vulkan-runtime-elf-report.txt"
)

require_vulkan_runtime() {
    local dest="$STAGE$PREFIX" lib="libvulkan.so.$VULKAN_VERSION"
    [[ -f "$dest/lib/$lib" && ! -L "$dest/lib/$lib" && \
       $(readlink "$dest/lib/libvulkan.so.1") == "$lib" && \
       $(readlink "$dest/lib/libvulkan.so") == libvulkan.so.1 ]] || \
        fail "Missing private Vulkan loader/relative links; run $0 runtime"
    [[ $(LC_ALL=C readelf -h "$dest/lib/$lib") == *AArch64* && \
       $(LC_ALL=C readelf -d "$dest/lib/$lib") == *'Library soname: [libvulkan.so.1]'* ]] || \
        fail "Private Vulkan loader must be AArch64 with SONAME libvulkan.so.1"
    [[ -f "$dest/share/j714s-gpu/vulkan-runtime/source-pins.txt" ]] || \
        fail "Private Vulkan runtime provenance is missing; run $0 runtime"
}

build() (
    prepare
    [[ -x "$TOOLS/bin/meson" ]] || fail "Run $0 bootstrap first"
    for tool in ninja pkg-config bison flex wayland-scanner llvm-config \
        aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ aarch64-linux-gnu-ar \
        aarch64-linux-gnu-strip readelf; do need "$tool"; done
    clean_build_env
    [[ -f "$HOST_DEPS/usr/lib/pkgconfig/LLVMSPIRVLib.pc" ]] || fail "Run $0 bootstrap-host first"
    local host_pc="$HOST_DEPS/usr/lib/pkgconfig"
    PKG_CONFIG_PATH="$host_pc" pkg-config --exists LLVMSPIRVLib || fail "Local translator metadata is unavailable"
    local llvm_version spirv_version
    llvm_version=$(llvm-config --version)
    spirv_version=$(PKG_CONFIG_PATH="$host_pc" pkg-config --modversion LLVMSPIRVLib)
    [[ $spirv_version == "${llvm_version%.*}".* ]] || \
        fail "LLVM $llvm_version and translator $spirv_version must match major.minor"
    cat > "$WORK/native.ini" <<EOF
[binaries]
c = '/usr/bin/gcc'
cpp = '/usr/bin/g++'
pkg-config = ['env', 'PKG_CONFIG_PATH=$host_pc', '/usr/bin/pkg-config']
llvm-config = '/usr/bin/llvm-config'
EOF
    cat > "$WORK/cross.ini" <<EOF
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '$SYSROOT'
pkg_config_libdir = ['$SYSROOT/usr/lib/pkgconfig', '$SYSROOT/usr/share/pkgconfig']
[built-in options]
c_args = ['--sysroot=$SYSROOT']
cpp_args = ['--sysroot=$SYSROOT', '-nostdinc++', '-isystem', '$SYSROOT/usr/include/c++/16.1.1', '-isystem', '$SYSROOT/usr/include/c++/16.1.1/aarch64-unknown-linux-gnu', '-isystem', '$SYSROOT/usr/include/c++/16.1.1/backward']
c_link_args = ['--sysroot=$SYSROOT', '-L$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib']
cpp_link_args = ['--sysroot=$SYSROOT', '-L$SYSROOT/usr/lib', '-Wl,-rpath-link,$SYSROOT/usr/lib']
EOF
    # A host-only build of the three shader generators from the SAME Mesa pin.
    local reconfigure=()
    [[ ! -f "$WORK/host-build/build.ninja" ]] || reconfigure=(--reconfigure)
    meson setup "${reconfigure[@]}" "$WORK/host-build" "$SRC" \
        --native-file "$WORK/native.ini" --prefix "$WORK/host-prefix" \
        --libdir lib --buildtype release --wrap-mode=nofallback \
        -Dplatforms= -Dgallium-drivers= -Dvulkan-drivers= -Dvideo-codecs= \
        -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
        -Dgles1=disabled -Dgles2=disabled -Dglvnd=disabled \
        -Dtools=asahi -Dllvm=enabled -Dshared-llvm=enabled \
        -Dmesa-clc=enabled -Dprecomp-compiler=enabled \
        -Dinstall-mesa-clc=true -Dinstall-precomp-compiler=true \
        -Dgallium-rusticl=false -Dbuild-tests=false
    ninja -C "$WORK/host-build" -j "$JOBS"
    meson install -C "$WORK/host-build" --no-rebuild
    reconfigure=()
    [[ ! -f "$WORK/target-build/build.ninja" ]] || reconfigure=(--reconfigure)
    meson setup "${reconfigure[@]}" "$WORK/target-build" "$SRC" \
        --native-file "$WORK/native.ini" --cross-file "$WORK/cross.ini" \
        --prefix "$PREFIX" --libdir lib --buildtype release --wrap-mode=nofallback \
        -Db_ndebug=true -Dplatforms=x11,wayland -Dgallium-drivers=asahi,zink \
        -Dvulkan-drivers=asahi -Dvulkan-layers= -Dvideo-codecs= \
        -Degl=enabled -Dgbm=enabled -Dglx=dri -Dgles1=enabled -Dgles2=enabled \
        -Dglvnd=enabled -Dglvnd-vendor-name=j714s_gpu \
        -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
        -Dgallium-rusticl=false -Dexpat=enabled -Dzstd=enabled \
        -Dlmsensors=disabled -Dlibunwind=disabled -Dvalgrind=disabled \
        -Dtools= -Dbuild-tests=false
    ninja -C "$WORK/target-build" -j "$JOBS"
    DESTDIR="$STAGE" meson install -C "$WORK/target-build" --no-rebuild
    build_vulkan_runtime
    package
)

package() (
    [[ -d "$STAGE$PREFIX/lib/dri" ]] || fail "Build and stage Mesa before packaging"
    require_vulkan_runtime
    local dest="$STAGE$PREFIX"
    mkdir -p "$dest/bin" "$dest/share/j714s-gpu"
    aarch64-linux-gnu-gcc --sysroot="$SYSROOT" -O2 -I"$SRC/include" \
        "$PROBES/contrib/pending/gpu/gl-native/tests/gl-native-smoke.c" \
        -L"$SYSROOT/usr/lib" -Wl,-rpath-link,"$SYSROOT/usr/lib" \
        -o "$dest/bin/gl-native-smoke" -lEGL -lGLESv2
    aarch64-linux-gnu-gcc --sysroot="$SYSROOT" -O2 -I"$SRC/include" \
        "$SRC/src/asahi/tools/native-gl-qualification/index-coverage.c" \
        -L"$SYSROOT/usr/lib" -Wl,-rpath-link,"$SYSROOT/usr/lib" \
        -o "$dest/bin/gl-index-coverage" -lEGL -lGLESv2
    cat > "$dest/bin/mesa-j714s-gpu" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
prefix=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-}
case "$mode" in native) driver=asahi ;; zink) driver=zink ;;
    *) echo "Usage: $0 native|zink COMMAND [ARGS...]" >&2; exit 2 ;; esac
shift
[[ $# -gt 0 ]] || { echo 'A command is required' >&2; exit 2; }
# Remove software forcing and all shim/preload state only in this subprocess.
unset LIBGL_ALWAYS_SOFTWARE LIBGL_ALWAYS_INDIRECT DRI_PRIME LD_PRELOAD \
    VK_ICD_FILENAMES ASAHI_SHIM_CHIP ASAHI_DEBUG HK_DEBUG
export ASAHI_M5_BRINGUP=1
export LD_LIBRARY_PATH="$prefix/lib"
export LIBGL_DRIVERS_PATH="$prefix/lib/dri"
export GALLIUM_DRIVER="$driver" MESA_LOADER_DRIVER_OVERRIDE="$driver"
export __EGL_VENDOR_LIBRARY_FILENAMES="$prefix/share/glvnd/egl_vendor.d/50_j714s_gpu.json"
export __GLX_VENDOR_LIBRARY_NAME=j714s_gpu
icds=("$prefix"/share/vulkan/icd.d/asahi_icd*.json)
[[ ${#icds[@]} == 1 && -f ${icds[0]} ]] || { echo 'Expected exactly one Asahi ICD' >&2; exit 2; }
export VK_DRIVER_FILES="${icds[0]}"
export MESA_SHADER_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mesa-j714s-gpu-043a4c58080c/$mode"
exec "$@"
SH
    chmod 755 "$dest/bin/mesa-j714s-gpu"
    printf 'Mesa %s\nSmoke source %s\nPrefix %s\n' "$MESA_SHA" "$PROBE_SHA" "$PREFIX" \
        > "$dest/share/j714s-gpu/source-pins.txt"
    cp "$WORK/cross.ini" "$WORK/native.ini" "$dest/share/j714s-gpu/"
    cp "$SRC/docs/license.rst" "$dest/share/j714s-gpu/mesa-license.rst"
    cp "$PROBES/LICENSE.md" "$dest/share/j714s-gpu/probe-licensing.txt"
    cp "$PROBES/LICENSES/MIT.txt" "$dest/share/j714s-gpu/probe-MIT.txt"
    cp "$PROBES/contrib/pending/gpu/gl-native/tests/gl-native-smoke.c" \
        "$dest/share/j714s-gpu/"
    # Static inspection only: record ELF architecture, NEEDED and symbol
    # versions for parent review against the saved target, never run a probe.
    python3 - "$dest" "$WORK/target-elf-report.txt" <<'PY'
import os, subprocess, sys
root, report = sys.argv[1:]
with open(report, 'w') as out:
    for directory, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(directory, name)
            if os.path.islink(path):
                continue
            with open(path, 'rb') as inp:
                if inp.read(4) != b'\x7fELF':
                    continue
            headers = subprocess.check_output(['readelf', '-h', path], text=True, env={**os.environ, 'LC_ALL': 'C'})
            if 'AArch64' not in headers:
                raise SystemExit('Non-aarch64 ELF in target stage: ' + path)
            out.write('\n== ' + os.path.relpath(path, root) + ' ==\n' + headers)
            out.flush()
            subprocess.run(['readelf', '-d', '-V', path], stdout=out, check=True)
PY
    sha256sum "$WORK/sysroot-inputs.sha256" > "$dest/share/j714s-gpu/sysroot-manifest.sha256"
    tar -C "$STAGE" -czf "$WORK/mesa-j714s-gpu-043a4c58080c.tar.gz" "${PREFIX#/}"
    echo "Staged only: $dest"
    echo "Archive: $WORK/mesa-j714s-gpu-043a4c58080c.tar.gz"
    echo "ELF dependency/version report: $WORK/target-elf-report.txt"
    echo 'No target installation or GPU execution performed.'
)

case "${1:-build}" in
    prepare) prepare ;;
    bootstrap) bootstrap ;;
    bootstrap-host) bootstrap_host ;;
    build) build ;;
    runtime) build_vulkan_runtime; package ;;
    package) package ;;
    help|-h|--help) printf '%s\n' \
        'prepare: immutable sources + private target sysroot snapshot' \
        'bootstrap: pinned Python tools in build/mesa-gpu/tools (network access)' \
        'bootstrap-host: signed LLVM23.1 translator in build/mesa-gpu/host-deps' \
        'build: native generators, aarch64 Mesa/runtime/probes, private /opt archive' \
        'runtime: build pinned Vulkan loader + delta archive; repackage staged Mesa (no Mesa rebuild)' \
        'package: compile functional probes and archive staged Mesa + required Vulkan runtime' \
        'Other matching host LLVM/Clang development prerequisites must already exist.' \
        'See script header for runtime commands. No automatic target deployment.' ;;
    *) fail "Unknown command: $1" ;;
esac
