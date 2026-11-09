#!/usr/bin/env bash
# Isolated J714s GPU/simpledrm session; leave the distro/DCP fallback unchanged.
set -euo pipefail

mesa=/opt/mesa-j714s-gpu-043a4c58080c
aquamarine=/opt/aquamarine-j714s-gpu-b77d67648336
hyprland=/usr/local/bin/Hyprland
session=/usr/bin/start-hyprland

if [[ ! -x "$mesa/bin/mesa-j714s-gpu" ||
      ! -r "$aquamarine/lib/libaquamarine.so.15" ||
      ! -x "$hyprland" || ! -x "$session" ]]; then
    printf 'Missing GPU desktop stack: %s, %s, %s, or %s\n' \
        "$mesa/bin/mesa-j714s-gpu" "$aquamarine/lib/libaquamarine.so.15" \
        "$hyprland" "$session" >&2
    exit 1
fi

# Zink uses the real Borealis Vulkan GPU; native Gallium is not desktop-qualified.
# The Mesa wrapper resets LD_LIBRARY_PATH, so add Aquamarine AFTER that wrapper.
exec "$mesa/bin/mesa-j714s-gpu" zink \
    /usr/bin/env LD_LIBRARY_PATH="$mesa/lib:$aquamarine/lib" \
    "$session" --path "$hyprland" -- "$@"
